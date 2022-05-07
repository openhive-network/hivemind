"""Conf handles reading run-time config and app-level settings."""

import logging
import re
from typing import Final

import configargparse

from hive.db.adapter import Db
from hive.utils.normalize import int_log_level, strtobool
from hive.utils.stats import DbStats

log = logging.getLogger(__name__)

SCHEMA_NAME: Final[str] = 'hivemind_app'


def _sanitized_conf(parser):
    """Formats parser config, redacting database url password."""
    out = parser.format_values()
    return re.sub(r'(?<=:)\w+(?=@)', '<redacted>', out)


class Conf:
    """Manages sync/server configuration via args, ENVs, and hive.conf."""

    def __init__(self):
        self._args = None
        self._env = None
        self._db = None
        self.arguments = None

    def init_argparse(self, strict=True, **kwargs):
        """Read hive config (CLI arg > ENV var > config)"""

        # pylint: disable=line-too-long
        parser = configargparse.get_arg_parser(default_config_files=['./hive.conf'], **kwargs)
        add = parser.add

        # runmodes: sync, server, status
        add('mode', nargs='*', default=['sync'])

        # common
        add('--database-url', env_var='DATABASE_URL', required=False, help='database connection url', default='')

        # server
        add('--http-server-port', type=int, env_var='HTTP_SERVER_PORT', default=8080)
        add(
            '--prometheus-port',
            type=int,
            env_var='PROMETHEUS_PORT',
            required=False,
            help='if specified, runs prometheus deamon on specified port, which provide statistic and performance data',
        )

        # sync
        add('--max-workers', type=int, env_var='MAX_WORKERS', help='max workers for batch requests', default=6)
        add('--max-batch', type=int, env_var='MAX_BATCH', help='max chunk size for batch requests', default=35)

        # --sync-to-s3 seems to be unnecessary
        add(
            '--sync-to-s3',
            type=strtobool,
            env_var='SYNC_TO_S3',
            help='alternative healthcheck for background sync service',
            default=False,
        )

        # test/debug
        add('--log-level', env_var='LOG_LEVEL', default='INFO')
        add(
            '--test-max-block',
            type=int,
            env_var='TEST_MAX_BLOCK',
            help='(debug) only sync to given block, for running sync test',
            default=None,
        )
        add(
            '--test-last-block-for-massive',
            type=int,
            env_var='TEST_LAST_BLOCK_MASSIVE',
            help='(debug) stop massive sync on a given LIB then synchronize in LIVE by processing blocks one at a time',
            default=None,
        )
        add('--test-profile', type=strtobool, env_var='TEST_PROFILE', help='(debug) profile execution', default=False)
        add(
            '--log-request-times',
            env_var='LOG_REQUEST_TIMES',
            help='(debug) allows to generate log containing request processing times',
            action='store_true',
        )
        add(
            '--log-op-calls',
            env_var='LOG_OP_CALLS',
            help='(debug) log operations calls and responses',
            action='store_true',
        )
        add(
            '--log-virtual-op-calls',
            env_var='LOG_VIRTUAL_OP_CALLS',
            help='(debug) log virtual op calls and responses',
            action='store_true',
        )
        add(
            '--mock-block-data-path',
            type=str,
            nargs='+',
            env_var='MOCK_BLOCK_DATA_PATH',
            help='(debug/testing) load additional data from block data file',
        )
        add(
            '--mock-vops-data-path',
            type=str,
            env_var='MOCK_VOPS_DATA_PATH',
            help='(debug/testing) load additional data from virtual operations data file',
        )
        add('--community-start-block', type=int, env_var='COMMUNITY_START_BLOCK', default=37500000)
        add(
            '--log_explain_queries',
            type=strtobool,
            env_var='LOG_EXPLAIN_QUERIES',
            help='(debug) Adds to log output of EXPLAIN ANALYZE for specific queries - only for db super user',
            default=False,
        )

        # logging
        add('--log-timestamp', help='Output timestamp in log', action='store_true')
        add('--log-epoch', help='Output unix epoch in log', action='store_true')
        add('--log-mask-sensitive-data', help='Mask sensitive data, e.g. passwords', action='store_true')

        add(
            '--pid-file',
            type=str,
            env_var='PID_FILE',
            help='Allows to dump current process pid into specified file',
            default=None,
        )

        add(
            '--auto-http-server-port',
            nargs='+',
            type=int,
            help='Hivemind will listen on first available port from this range',
        )

        # needed for e.g. tests - other args may be present
        args = parser.parse_args() if strict else parser.parse_known_args()[0]

        self._args = vars(args)
        self.arguments = parser._actions

        # configure logger and print config
        root = logging.getLogger()
        root.setLevel(self.log_level())

        try:
            if 'auto_http_server_port' in vars(args) and vars(args)['auto_http_server_port'] is not None:
                port_range = vars(args)['auto_http_server_port']
                port_range_len = len(port_range)
                if port_range_len == 0 or port_range_len > 2:
                    raise ValueError("auto-http-server-port expect maximum two values, minimum one")
                if port_range_len == 2 and port_range[0] > port_range[1]:
                    raise ValueError("port min value is greater than port max value")
        except Exception as ex:
            root.error(f"Value error: {ex}")
            exit(1)

        # Print command line args, but on continuous integration server
        # hide db connection string.
        from sys import argv

        if self.get('log_mask_sensitive_data'):
            my_args = []
            upcoming_connection_string = False
            for elem in argv[1:]:
                if upcoming_connection_string:
                    upcoming_connection_string = False
                    my_args.append('MASKED')
                    continue
                if elem == '--database-url':
                    upcoming_connection_string = True
                my_args.append(elem)
            root.info("Used command line args: %s", " ".join(my_args))
        else:
            root.info("Used command line args: %s", " ".join(argv[1:]))

        # uncomment for full list of program args
        # args_list = ["--" + k + " " + str(v) for k,v in vars(args).items()]
        # root.info("Full command line args: %s", " ".join(args_list))

        if self.mode() == 'server':
            # DbStats.SLOW_QUERY_MS = 750
            DbStats.SLOW_QUERY_MS = 200  # TODO

    def __enter__(self):
        return self

    def __exit__(self, exc_type, value, traceback):
        self.disconnect()

    def args(self):
        """Get the raw Namespace object as generated by configargparse"""
        return self._args

    def db(self):
        """Get a configured instance of Db."""
        if self._db is None:
            url = self.get('database_url')
            enable_autoexplain = self.get('log_explain_queries')
            assert url, '--database-url (or DATABASE_URL env) not specified'
            self._db = Db(url, "root db creation", enable_autoexplain)
            log.info("The database instance is created...")

        return self._db

    def get(self, param):
        """Reads a single property, e.g. `database_url`."""
        assert self._args, "run init_argparse()"
        return self._args[param]

    def mode(self):
        """Get the CLI runmode.

        - `server`: API server
        - `sync`: db sync process
        - `status`: status info dump
        """
        return '/'.join(self.get('mode'))

    def log_level(self):
        """Get `logger`s internal int level from config string."""
        return int_log_level(self.get('log_level'))

    def pid_file(self):
        """Get optional pid_file name to put current process pid in"""
        return self._args.get("pid_file", None)

    def generate_completion(self):
        arguments = []
        for arg in self.arguments:
            arguments.extend(arg.option_strings)
        arguments = " ".join(arguments)
        with open('hive-completion.bash', 'w') as file:
            file.writelines(
                [
                    "#!/bin/bash\n",
                    "# to run type: source hive-completion.bash\n\n",
                    "# if you want to have completion everywhere, execute theese commands\n",
                    "# ln $PWD/hive-completion.bash $HOME/.local/\n",
                    '# echo "source $HOME/.local/hive-completion.bash" >> $HOME/.bashrc\n',
                    "# source $HOME/.bashrc\n\n" f'complete -f -W "{arguments}" hive\n',
                    "\n",
                ]
            )

    def disconnect(self):
        if self._db is not None:
            self._db.close()
            self._db.close_engine()
            self._db = None
            log.info("The database is disconnected...")

"""Conf handles reading run-time config and app-level settings."""

import re
import logging
import configargparse

from hive.steem.client import SteemClient
from hive.db.adapter import Db
from hive.utils.normalize import strtobool, int_log_level
from hive.utils.stats import DbStats

def _sanitized_conf(parser):
    """Formats parser config, redacting database url password."""
    out = parser.format_values()
    return re.sub(r'(?<=:)\w+(?=@)', '<redacted>', out)

class Conf():
    """ Manages sync/server configuration via args, ENVs, and hive.conf. """

    @classmethod
    def init_argparse(cls, strict=True, **kwargs):
        """Read hive config (CLI arg > ENV var > config)"""

        #pylint: disable=line-too-long
        parser = configargparse.get_arg_parser(
            default_config_files=['./hive.conf'],
            **kwargs)
        add = parser.add

        # runmodes: sync, server, status
        add('mode', nargs='*', default=['sync'])

        # common
        add('--database-url', env_var='DATABASE_URL', required=False, help='database connection url', default='')
        add('--steemd-url', env_var='STEEMD_URL', required=False, help='steemd/jussi endpoint', default='{"default" : "https://api.hive.blog"}')
        add('--muted-accounts-url', env_var='MUTED_ACCOUNTS_URL', required=False, help='url to flat list of muted accounts', default='https://raw.githubusercontent.com/hivevectordefense/irredeemables/master/full.txt')
        add('--blacklist-api-url', env_var='BLACKLIST_API_URL', required=False, help='url to access blacklist api', default='https://blacklist.usehive.com')

        # server
        add('--http-server-port', type=int, env_var='HTTP_SERVER_PORT', default=8080)
        add('--prometheus-port', type=int, env_var='PROMETHEUS_PORT', required=False, help='if specified, runs prometheus deamon on specified port, which provide statistic and performance data')

        # sync
        add('--max-workers', type=int, env_var='MAX_WORKERS', help='max workers for batch requests', default=4)
        add('--max-batch', type=int, env_var='MAX_BATCH', help='max chunk size for batch requests', default=50)
        add('--trail-blocks', type=int, env_var='TRAIL_BLOCKS', help='number of blocks to trail head by', default=2)
        add('--sync-to-s3', type=strtobool, env_var='SYNC_TO_S3', help='alternative healthcheck for background sync service', default=False)

        # test/debug
        add('--log-level', env_var='LOG_LEVEL', default='INFO')
        add('--test-disable-sync', type=strtobool, env_var='TEST_DISABLE_SYNC', help='(debug) skip sync and sweep; jump to block streaming', default=False)
        add('--test-max-block', type=int, env_var='TEST_MAX_BLOCK', help='(debug) only sync to given block, for running sync test', default=None)
        add('--test-profile', type=strtobool, env_var='TEST_PROFILE', help='(debug) profile execution', default=False)
        add('--log-virtual-op-calls', type=strtobool, env_var='LOG_VIRTUAL_OP_CALLS', help='(debug) log virtual op calls and responses', default=False)
        add('--mock-block-data-path', type=str, env_var='MOCK_BLOCK_DATA_PATH', help='(debug/testing) load additional data from block data file')
        add('--mock-vops-data-path', type=str, env_var='MOCK_VOPS_DATA_PATH', help='(debug/testing) load additional data from virtual operations data file')

        # logging
        add('--log-timestamp', help='Output timestamp in log', action='store_true')
        add('--log-epoch', help='Output unix epoch in log', action='store_true')
        add('--log-mask-sensitive-data', help='Mask sensitive data, e.g. passwords', action='store_true')

        add('--pid-file', type=str, env_var='PID_FILE', help='Allows to dump current process pid into specified file', default=None)

        add('--auto-http-server-port', nargs='+', type=int, help='Hivemind will listen on first available port from this range')

        # needed for e.g. tests - other args may be present
        args = (parser.parse_args() if strict
                else parser.parse_known_args()[0])

        conf = Conf(args=vars(args), arguments=parser._actions)

        # configure logger and print config
        root = logging.getLogger()
        root.setLevel(conf.log_level())

        try:
            if 'auto_http_server_port' in vars(args) and vars(args)['auto_http_server_port'] is not None:
                port_range = vars(args)['auto_http_server_port']
                port_range_len = len(port_range)
                if port_range_len == 0 or port_range_len > 2:
                    raise ValueError("auto-http-server-port expect maximum two values, minimum one")
                if port_range_len == 2 and port_range[0] > port_range[1]:
                    raise ValueError("port min value is greater than port max value")
        except Exception as ex:
            root.error("Value error: {}".format(ex))
            exit(1)

        # Print command line args, but on continuous integration server
        # hide db connection string.
        from sys import argv
        if conf.get('log_mask_sensitive_data'):
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
        #args_list = ["--" + k + " " + str(v) for k,v in vars(args).items()]
        #root.info("Full command line args: %s", " ".join(args_list))

        if conf.mode() == 'server':
            #DbStats.SLOW_QUERY_MS = 750
            DbStats.SLOW_QUERY_MS = 200 # TODO

        return conf

    @classmethod
    def init_test(cls):
        """Initialize hive config for testing."""
        return cls.init_argparse(strict=False)

    def __init__(self, args, env=None, arguments=None):
        self._args = args
        self._env = env
        self._db = None
        self._steem = None
        self.arguments = arguments

    def args(self):
        """Get the raw Namespace object as generated by configargparse"""
        return self._args

    def steem(self):
        """Get a SteemClient instance, lazily initialized"""
        if not self._steem:
            from json import loads
            self._steem = SteemClient(
                url=loads(self.get('steemd_url')),
                max_batch=self.get('max_batch'),
                max_workers=self.get('max_workers'))
        return self._steem

    def db(self):
        """Get a configured instance of Db."""
        if not self._db:
            url = self.get('database_url')
            assert url, ('--database-url (or DATABASE_URL env) not specified; '
                         'e.g. postgresql://user:pass@localhost:5432/hive')
            self._db = Db(url)
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
            file.writelines([
                "#!/bin/bash\n",
                "# to run type: source hive-completion.bash\n\n",
                "# if you want to have completion everywhere, execute theese commands\n",
                "# ln $PWD/hive-completion.bash $HOME/.local/\n",
                '# echo "source $HOME/.local/hive-completion.bash" >> $HOME/.bashrc\n',
                "# source $HOME/.bashrc\n\n"
                f'complete -f -W "{arguments}" hive\n',
                "\n"
            ])

#!/usr/bin/env python3

"""CLI service router"""

import atexit
import faulthandler
import logging
import os
import time

from hive.conf import Conf
from hive.db.adapter import Db
from hive.utils.stats import PrometheusClient

log = logging.getLogger(__name__)


def setup_logging(conf):
    """Setup logging with timestamps"""

    timestamp = conf.get('log_timestamp')
    epoch = conf.get('log_epoch')
    if timestamp and epoch:
        datefmt = '%Y-%m-%d %H:%M:%S'
        timezone = time.strftime('%z')
        fmt = f'%(asctime)s.%(msecs)03d{timezone} %(created).6f %(levelname)s - %(name)s:%(lineno)d - %(message)s'
        logging.basicConfig(format=fmt, datefmt=datefmt)
    elif timestamp:
        datefmt = '%Y-%m-%d %H:%M:%S'
        timezone = time.strftime('%z')
        fmt = f'%(asctime)s.%(msecs)03d{timezone} %(levelname)s - %(name)s:%(lineno)d - %(message)s'
        logging.basicConfig(format=fmt, datefmt=datefmt)
    elif epoch:
        fmt = '%(created).6f %(levelname)s - %(name)s:%(lineno)d - %(message)s'
        logging.basicConfig(format=fmt)
    else:
        fmt = '%(levelname)s - %(name)s:%(lineno)d - %(message)s'
        logging.basicConfig(format=fmt)


def run() -> None:
    """Run the service specified in the `--mode` argument, logging why and with which code the process ends.

    Python waits for the non-daemon threads still running when the main thread
    ends, so the process may end long after the reason is logged; the exit code
    is logged again when it does. A fatal signal dumps every thread's stack
    (faulthandler); SIGKILL leaves no trace.
    """
    faulthandler.enable()
    try:
        _run()
    except SystemExit as exc:
        _log_exit(_system_exit_code(exc), f'SystemExit({exc.code!r})')
        raise
    except KeyboardInterrupt:
        _log_exit(_SIGINT_EXIT_CODE, 'KeyboardInterrupt')
        raise
    except BaseException as exc:
        _log_exit(1, f'{type(exc).__name__}: {exc}')
        raise
    _log_exit(0, 'finished')


# Python ends a process that a KeyboardInterrupt ended by re-raising SIGINT.
_SIGINT_EXIT_CODE = 130


def _system_exit_code(exc: SystemExit) -> int:
    if exc.code is None:
        return 0
    return exc.code if isinstance(exc.code, int) else 1


def _log_exit(code: int, reason: str) -> None:
    level = logging.INFO if code == 0 else logging.ERROR
    log.log(level, "Main thread ended (%s); exit code %d", reason, code)
    main_ended = time.perf_counter()
    atexit.register(
        lambda: log.log(
            level,
            "Process exiting with code %d, %.1fs after the main thread ended (%s)",
            code,
            time.perf_counter() - main_ended,
            reason,
        )
    )


def _run() -> None:
    with Conf() as conf:
        conf.init_argparse()
        mode = conf.mode()
        PrometheusClient(conf.get('prometheus_port'))

        setup_logging(conf)

        if mode == 'completion':
            conf.generate_completion()
            return

        pid_file_name = conf.pid_file()
        if pid_file_name is not None:
            fh = open(pid_file_name, 'w')
            if fh is None:
                print("Cannot write into specified pid_file: %s", pid_file_name)
            else:
                pid = os.getpid()
                fh.write(str(pid))
                fh.close()

        if conf.get('test_profile'):
            from hive.utils.profiler import Profiler

            with Profiler():
                launch_mode(mode, conf)
        else:
            launch_mode(mode, conf)


def launch_mode(mode, conf):
    """Launch a routine as indicated by `mode`."""
    if mode == 'build_schema':
        # Calculation of number of maximum connection and closing a database
        # In next step the database will be opened with correct number of connections
        Db.set_max_connections(conf.db())
        conf.disconnect()

        Db.set_shared_instance(conf.db())

        from hive.indexer.sync import SyncHiveDb

        with SyncHiveDb(conf=conf, enter_sync=False, upgrade_schema=False) as schema_builder:
            schema_builder.build_database_schema()

    elif mode == 'upgrade_schema':
        # Calculation of number of maximum connection and closing a database
        # In next step the database will be opened with correct number of connections
        Db.set_max_connections(conf.db())
        conf.disconnect()

        Db.set_shared_instance(conf.db())

        from hive.indexer.sync import SyncHiveDb

        with SyncHiveDb(conf=conf, enter_sync=False, upgrade_schema=True) as schema_builder:
            schema_builder.build_database_schema()

    elif mode == 'sync':
        # Calculation of number of maximum connection and closing a database
        # In next step the database will be opened with correct number of connections
        Db.set_max_connections(conf.db())
        conf.disconnect()

        Db.set_shared_instance(conf.db())
        from hive.indexer.sync import SyncHiveDb

        with SyncHiveDb(conf=conf, enter_sync=True, upgrade_schema=False) as sync:
            sync.run()

    elif mode == 'status':
        from hive.db.db_state import DbState

        print(DbState.status())

    else:
        raise Exception(f"unknown run mode {mode}. Accepted run modes are: `build_schema', `sync', `status'")


if __name__ == '__main__':
    run()

#!/usr/bin/env python3

"""CLI service router"""

import logging
import os
import time

from hive.conf import Conf
from hive.db.adapter import Db
from hive.utils.stats import PrometheusClient

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


def run():
    """Run the service specified in the `--mode` argument."""
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
        with SyncHiveDb(conf=conf, enter_sync = False, upgrade_schema = False) as schema_builder:
            schema_builder.build_database_schema()

    elif mode == 'upgrade_schema':
        # Calculation of number of maximum connection and closing a database
        # In next step the database will be opened with correct number of connections
        Db.set_max_connections(conf.db())
        conf.disconnect()

        Db.set_shared_instance(conf.db())

        from hive.indexer.sync import SyncHiveDb
        with SyncHiveDb(conf=conf, enter_sync = False, upgrade_schema = True) as schema_builder:
            schema_builder.build_database_schema()

    elif mode == 'sync':
        # Calculation of number of maximum connection and closing a database
        # In next step the database will be opened with correct number of connections
        Db.set_max_connections(conf.db())
        conf.disconnect()

        Db.set_shared_instance(conf.db())
        from hive.indexer.sync import SyncHiveDb
        with SyncHiveDb(conf=conf, enter_sync = True, upgrade_schema = False) as sync:
            sync.run()

    elif mode == 'status':
        from hive.db.db_state import DbState

        print(DbState.status())

    else:
        raise Exception(f"unknown run mode {mode}. Accepted run modes are: `build_schema', `sync', `status'")


if __name__ == '__main__':
    run()

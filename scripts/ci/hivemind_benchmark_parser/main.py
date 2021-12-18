import argparse
import asyncio
import datetime
import logging
from pathlib import Path
import socket
import sys
from time import perf_counter as perf

import common
from db_adapter import Db
import server_log_parser
import sync_log_parser

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger()


def init_argparse(args) -> argparse.Namespace:
    p = argparse.ArgumentParser(description='Parse a benchmark log file.',
                                formatter_class=argparse.RawTextHelpFormatter)

    req = p.add_argument_group('required arguments')
    add = req.add_argument
    add('-m', '--mode', type=int, required=True, choices=[1, 2, 3],
        help='1 - server_log_parser,\n2 - sync_log_parser,\n3 - replay_benchmark_parser')
    add('-f', '--file', type=str, required=True, metavar='FILE_PATH', help='Source .log file path.')
    add('-db', '--database_url', type=str, required=True, metavar='URL', help='Database URL.')
    add('--desc', type=str, required=True, help='Benchmark description.')
    add('--exec-env-desc', type=str, required=True, help='Execution environment description.')
    add('--server-name', type=str, required=True, help='Server name when benchmark has been performed')
    add('--app-version', type=str, required=True)
    add('--testsuite-version', type=str, required=True)

    return p.parse_args(args)


async def insert_benchmark_description(db: Db, args: argparse.Namespace, timestamp: datetime.datetime) -> int:
    return await common.insert_row_with_returning(db,
                                                  table='public.benchmark_description',
                                                  cols_args={'description': args.desc,
                                                             'execution_environment_description': args.exec_env_desc,
                                                             'timestamp': timestamp.strftime('%Y/%m/%d, %H:%M:%S'),
                                                             'server_name': args.server_name,
                                                             'app_version': args.app_version,
                                                             'testsuite_version': args.testsuite_version,
                                                             'runner': socket.gethostname(),
                                                             },
                                                  additional=' RETURNING id',
                                                  )


async def main():
    start = perf()
    timestamp = datetime.datetime.now()

    args = init_argparse(sys.argv[1:])
    log.info(f' | [START ARGS]={vars(args)}')

    db = await Db.create(args.database_url)

    benchmark_id = await insert_benchmark_description(db, args, timestamp)

    if args.mode == 1:
        log.info(' | [MODE]=server_log_parser')
        await server_log_parser.main(db, file=Path(args.file), benchmark_id=benchmark_id)
    elif args.mode == 2:
        log.info(' | [MODE]=sync_log_parser')
        await sync_log_parser.main(db, file=Path(args.file), benchmark_id=benchmark_id)
    elif args.mode == 3:
        log.info('[ | [MODE]=replay_benchmark_parser')

    db.close()
    await db.wait_closed()
    log.info(f'Execution time: {perf() - start:.6f}s')


if __name__ == '__main__':
    asyncio.run(main())

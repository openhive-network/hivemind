import argparse
import asyncio
import datetime
import logging
import sys
from time import perf_counter as perf

from db_adapter import Db
import parser

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def init_argparse(args) -> argparse.Namespace:
    p = argparse.ArgumentParser(description='Parse a benchmark log file.',
                                formatter_class=argparse.RawTextHelpFormatter)

    req = p.add_argument_group('required arguments')
    add = req.add_argument
    add('-m', '--mode', type=int, required=True, choices=[1, 2, 3],
        help='1 - hivemind-server,\n2 - hivemind-sync,\n3 - not implemented')
    add('-f', '--file', type=str, required=True, metavar='FILE_PATH', help='Source .log file path.')
    add('-db', '--database_url', type=str, required=True, metavar='URL', help='Database URL.')
    add('--desc', type=str, required=True, help='Benchmark description.')
    add('--exec-env-desc', type=str, required=True, help='Execution environment description.')
    add('--server-name', type=str, required=True, help='Server name when benchmark has been performed')
    add('--app-version', type=str, required=True)
    add('--testsuite-version', type=str, required=True)

    return p.parse_args(args)


async def main():
    start = perf()
    timestamp = datetime.datetime.now()

    args = init_argparse(sys.argv[1:])
    log.info(f'Arguments given:\n{vars(args)}')

    db = await Db.create(args.database_url)

    if args.mode == 1:
        log.info('[MODE]: hivemind-server')
        await parser.main(args, db, timestamp)
    elif args.mode == 2:
        log.info('[MODE]: hivemind-sync')
    elif args.mode == 3:
        log.info('[MODE]: not implemented')

    db.close()
    await db.wait_closed()
    log.info(f'Execution time: {perf() - start:.6f}s')


if __name__ == '__main__':
    asyncio.run(main())

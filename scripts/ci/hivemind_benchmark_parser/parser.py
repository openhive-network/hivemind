import argparse
import dataclasses
import datetime
from hashlib import sha256
import json
import logging
from pathlib import Path
import re
import socket
import sys
from time import perf_counter as perf
from typing import List, Optional, Tuple

from db_adapter import Db


@dataclasses.dataclass
class ParsedRequest:
    api: str
    method: str
    parameters: str
    total_time: float
    id: int = None

    def __iter__(self):
        return iter([self.api, self.method, self.parameters, self.total_time])

    def hash(self) -> str:
        return calculate_hash(f'{self.api},{self.method},{self.parameters}')


@dataclasses.dataclass
class Benchmark:
    description: str
    execution_environment_description: str
    timestamp: str
    server_name: str
    app_version: str
    testsuite_version: str
    runner: str


def init_argparse(args) -> argparse.Namespace:
    p = argparse.ArgumentParser(description='Parse a benchmark log file.')

    req = p.add_argument_group('required arguments')
    add = req.add_argument
    add('-f', '--file', type=str, required=True, metavar='FILE_PATH', help='Source .log file path.')
    add('-db', '--database_url', type=str, metavar="URL", help='Database URL.')
    add('--desc', type=str, required=True, help='Benchmark description.')
    add('--exec-env-desc', type=str, required=True, help='Execution environment description.')
    add('--server-name', type=str, required=True, help='Server name when benchmark has been performed')
    add('--app-version', type=str, required=True)
    add('--testsuite-version', type=str, required=True)

    return p.parse_args(args)


def get_lines_from_log_file(file_path: Path) -> List[str]:
    with open(file_path, 'r') as file:
        log_lines = file.readlines()
    return log_lines


def parse_log_line(line: str) -> Optional[ParsedRequest]:
    result = re.match(r'Request: (.*) processed in ([\.\d]+)s', line)
    if not result:
        return None

    try:
        request = json.loads(result[1])
    except json.JSONDecodeError:
        logging.warning(f'Request rejected from parsing: {result[1]}')
        return None

    if request['method'] == 'call':
        method = request['method']
        if isinstance(request['params'], list):
            api = request['params'][0]
        else:
            api = request['params']['api']
    else:
        api, method = request['method'].split('.')

    return ParsedRequest(
        api=api,
        method=method,
        parameters=json.dumps(request['params']),
        total_time=float(result[2]),
    )


def parse_log_lines(lines: List[str]) -> List[ParsedRequest]:
    parsed_list = []
    identical_requests = {}
    for line in lines:
        if parsed := parse_log_line(line):
            if (hash := parsed.hash()) not in identical_requests:
                identical_requests[hash] = [parsed]
            else:
                identical_requests[hash].append(parsed)

    for _, lst in identical_requests.items():
        id = 1
        for response in lst:
            response.id = id
            parsed_list.append(response)
            id += 1

    return parsed_list


def retrieve_cols_and_params(values: dict) -> Tuple[str, str]:
    fields = list(values.keys())
    cols = ', '.join([k for k in fields])
    params = ', '.join([f':{k}' for k in fields])
    return cols, params


async def insert_row(_db: Db, table: str, values: dict) -> None:
    cols, params = retrieve_cols_and_params(values)
    sql = f"INSERT INTO {table} ({cols}) VALUES ({params});"
    await _db.query(sql, **values)


async def insert_row_with_returning(_db: Db, table: str, values: dict, additional: str = '') -> int:
    cols, params = retrieve_cols_and_params(values)
    sql = f"INSERT INTO {table} ({cols}) VALUES ({params}) {additional};"
    return await _db.query_one(sql, **values)


async def insert_testcases(_db: Db, parsed_list: List[ParsedRequest]) -> List[int]:
    ids = []
    for p in parsed_list:
        values = dict(api=p.api,
                      method=p.method,
                      parameters=p.parameters,
                      # ',' because bridg.emethod != bridge.method
                      hash=calculate_hash(f'{p.api},{p.method},{p.parameters}'),
                      )
        ids.append(await insert_row_with_returning(_db,
                                                   table='public.testcase',
                                                   values=values,
                                                   additional=' ON CONFLICT (hash) DO UPDATE '
                                                              'SET api = public.testcase.api RETURNING id;',
                                                   ))
        # because the insert above increments public.testcase_id_seq everytime
        await _db.query("SELECT setval('public.testcase_id_seq', MAX(id)) FROM public.testcase;")
    return ids


def create_benchmark(args: argparse.Namespace) -> Benchmark:
    return Benchmark(description=args.desc,
                     execution_environment_description=args.exec_env_desc,
                     timestamp=datetime.datetime.now().strftime('%Y/%m/%d, %H:%M:%S'),
                     server_name=args.server_name,
                     app_version=args.app_version,
                     testsuite_version=args.testsuite_version,
                     runner=socket.gethostname())


def calculate_hash(text: str) -> str:
    return sha256(text.encode('utf8')).hexdigest()


async def main():
    start = perf()
    logging.getLogger().setLevel(logging.INFO)
    log = logging.getLogger(__name__)

    args = init_argparse(sys.argv[1:])
    log.info(f'Arguments given:\n{vars(args)}')
    benchmark = create_benchmark(args)

    log_lines = get_lines_from_log_file(Path(args.file))
    parsed_list = parse_log_lines(log_lines)

    if db_url := args.database_url:
        _db = await Db.create(db_url)
        benchmark_id = await insert_row_with_returning(_db,
                                                       table='public.benchmark_description',
                                                       values=vars(benchmark),
                                                       additional=' RETURNING id',
                                                       )
        testcase_ids = await insert_testcases(_db, parsed_list)

        for idx, testcase_id in enumerate(testcase_ids):
            # execution_time in ms
            await insert_row(_db,
                             'public.benchmark_times',
                             dict(benchmark_id=benchmark_id,
                                  testcase_id=testcase_id,
                                  request_id=parsed_list[idx].id,
                                  execution_time=round(parsed_list[idx].total_time * 10 ** 3),
                                  ))

        _db.close()
        await _db.wait_closed()
        log.info(f'Execution time: {perf() - start:.6f}s')

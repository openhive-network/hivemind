from __future__ import annotations

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
from typing import Optional

from db_adapter import Db


@dataclasses.dataclass
class ParsedTestcase:
    api: str
    method: str
    parameters: str
    total_time: float
    id: int = None
    hash: str = None

    def __post_init__(self):
        self.hash = calculate_hash(self.api, self.method, self.parameters)

    def __iter__(self):
        return iter([self.api, self.method, self.parameters, self.total_time])


def init_argparse(args) -> argparse.Namespace:
    p = argparse.ArgumentParser(description='Parse a benchmark log file.')

    req = p.add_argument_group('required arguments')
    add = req.add_argument
    add('-f', '--file', type=str, required=True, metavar='FILE_PATH', help='Source .log file path.')
    add('-db', '--database_url', type=str, required=True, metavar='URL', help='Database URL.')
    add('--desc', type=str, required=True, help='Benchmark description.')
    add('--exec-env-desc', type=str, required=True, help='Execution environment description.')
    add('--server-name', type=str, required=True, help='Server name when benchmark has been performed')
    add('--app-version', type=str, required=True)
    add('--testsuite-version', type=str, required=True)

    return p.parse_args(args)


def get_lines_from_log_file(file_path: Path) -> list[str]:
    with open(file_path, 'r') as file:
        log_lines = file.readlines()
    return log_lines


def parse_log_line(line: str) -> Optional[ParsedTestcase]:
    """Parses single log line into a ParsedTestcase object or returns None if it can't be parsed"""

    result = re.match(r'Request: (.*) processed in ([\.\d]+)s', line)
    if not result:
        return None

    try:
        request = json.loads(result[1])
    except json.JSONDecodeError:
        logging.warning(f'[Testcase rejected from parsing]: {result[0]}')
        return None

    if request['method'] == 'call':
        method = request['method']
        if isinstance(request['params'], list):
            api = request['params'][0]
        else:
            api = request['params']['api']
    else:
        api, method = request['method'].split('.')

    return ParsedTestcase(api=api,
                          method=method,
                          parameters=json.dumps(request['params']),
                          total_time=float(result[2]),
                          )


def prepare_db_records_from_log_lines(lines: list[str]) -> list[ParsedTestcase]:
    parsed_list = []
    identical_requests = {}
    for line in lines:
        if parsed := parse_log_line(line):
            if (hash := parsed.hash) not in identical_requests:
                identical_requests[hash] = [parsed]
            else:
                identical_requests[hash].append(parsed)

    for lst in identical_requests.values():
        id = 1
        for parsed in lst:
            parsed.id = id  # to distinguish them from each other in the database
            parsed_list.append(parsed)
            id += 1

    return parsed_list


def retrieve_cols_and_params(cols_args: dict[str, str]) -> tuple[str, str]:
    """
    Parse dict of cols_args into a two separated strings formats that are needed when
    building a SQL for '_query' method of db_adapter.
    """

    fields = list(cols_args.keys())
    cols = ', '.join([k for k in fields])
    params = ', '.join([f':{k}' for k in fields])
    return cols, params


async def insert_row(db: Db, table: str, cols_args: dict) -> None:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params});'
    await db.query(sql, **cols_args)


async def insert_row_with_returning(db: Db, table: str, cols_args: dict, additional: str = '') -> int:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params}) {additional};'
    return await db.query_one(sql, **cols_args)


async def insert_requests(db: Db, parsed_list: list[ParsedTestcase]) -> list[int]:
    """
    Inserts request data from the ParsedTestcase objects into the 'request' table. The primary key is always incremented
    during insertion (even if there is a conflict) and after the INSERT query, we have to send another query
    to set the PK value to the last one.

    This function returns the list of inserted requests primary keys (request.id column).
    """
    request_ids = []  # primary keys of 'request' table
    for p in parsed_list:
        request_ids.append(await insert_row_with_returning(db,
                                                           table='public.request',
                                                           cols_args={'api': p.api,
                                                                      'method': p.method,
                                                                      'parameters': p.parameters,
                                                                      'hash': p.hash,
                                                                      },
                                                           additional=' ON CONFLICT (hash) DO UPDATE '
                                                                      'SET api = public.request.api RETURNING id;',
                                                           ))
        # because the insert above increments public.request_id_seq everytime
        await db.query("SELECT setval('public.request_id_seq', MAX(id)) FROM public.request;")
    return request_ids


def benchmark_description(args: argparse.Namespace) -> dict[str, str]:
    return {'description': args.desc,
            'execution_environment_description': args.exec_env_desc,
            'timestamp': datetime.datetime.now().strftime('%Y/%m/%d, %H:%M:%S'),
            'server_name': args.server_name,
            'app_version': args.app_version,
            'testsuite_version': args.testsuite_version,
            'runner': socket.gethostname(),
            }


def calculate_hash(*args) -> str:
    return sha256(str(args).encode('utf-8')).hexdigest()


async def main():
    start = perf()
    logging.getLogger().setLevel(logging.INFO)
    log = logging.getLogger(__name__)

    args = init_argparse(sys.argv[1:])
    log.info(f'Arguments given:\n{vars(args)}')

    log_lines = get_lines_from_log_file(Path(args.file))
    parsed_list = prepare_db_records_from_log_lines(log_lines)

    if db_url := args.database_url:
        db = await Db.create(db_url)
        benchmark_id = await insert_row_with_returning(db,
                                                       table='public.benchmark_description',
                                                       cols_args=benchmark_description(args),
                                                       additional=' RETURNING id',
                                                       )
        request_ids = await insert_requests(db, parsed_list)

        for id, request_id in enumerate(request_ids):
            await insert_row(db,
                             'public.request_times',
                             {'benchmark_id': benchmark_id,
                              'request_id': request_id,
                              'testcase_id': parsed_list[id].id,
                              'execution_time': round(parsed_list[id].total_time * 10 ** 3),  # execution_time in ms
                              })

        db.close()
        await db.wait_closed()
        log.info(f'Execution time: {perf() - start:.6f}s')

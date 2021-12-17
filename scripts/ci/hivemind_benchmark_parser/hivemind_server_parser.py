from __future__ import annotations

import dataclasses
import json
import logging
import re
from typing import Optional

import common
from db_adapter import Db

log = logging.getLogger(__name__)


@dataclasses.dataclass
class ParsedTestcase:
    api: str
    method: str
    parameters: str
    total_time: float
    id: int = None

    def __post_init__(self):
        self.hash = common.calculate_hash(self.api, self.method, self.parameters)


def parse_log_line(line: str) -> Optional[ParsedTestcase]:
    result = re.match(r'Request: (.*) processed in ([\.\d]+)s', line)
    if not result:
        return None

    try:
        request = json.loads(result[1])
    except json.JSONDecodeError:
        logging.warning(f'[REJECTED FROM PARSING]: {result[0]}')
        return None

    if request['method'] == 'call':
        if isinstance(request['params'], list):
            api = request['params'][0]
            method = request['params'][1]
            params = request['params'][2]
        else:
            api = request['params']['api']
            method = request['params']['method']
            params = request['params']['params']
    else:
        api, method = request['method'].split('.')
        params = request['params']

    return ParsedTestcase(api=api,
                          method=method,
                          parameters=json.dumps(params),
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


async def insert_testcases(db: Db, parsed_list: list[ParsedTestcase]) -> list[str]:
    """
    Inserts request data from the ParsedTestcase objects into the 'testcase' table.
    This function returns the list of inserted testcases primary keys (testcase.hash column).
    """
    testcase_pks = []  # primary keys of 'testcase' table
    for p in parsed_list:
        testcase_pks.append(
            str(await common.insert_row_with_returning(db=db,
                                                       table='public.testcase',
                                                       cols_args={'hash': p.hash,
                                                                  'caller': p.api,
                                                                  'method': p.method,
                                                                  'params': p.parameters,
                                                                  },
                                                       additional=' ON CONFLICT (hash) DO UPDATE '
                                                                  'SET caller = public.testcase.caller RETURNING hash;',
                                                       )))
    return testcase_pks


async def main(file, db, benchmark_id):
    log_lines = common.get_lines_from_log_file(file)
    parsed_list = prepare_db_records_from_log_lines(log_lines)

    testcase_pks = await insert_testcases(db, parsed_list)

    for id, hash in enumerate(testcase_pks):
        await common.insert_row(db=db,
                                table='public.benchmark_values',
                                cols_args={'benchmark_description_id': benchmark_id,
                                           'testcase_hash': hash,
                                           'occurrence_number': parsed_list[id].id,
                                           'value': round(parsed_list[id].total_time * 10 ** 3),  # execution_time in ms
                                           'unit': 'ms',
                                           })

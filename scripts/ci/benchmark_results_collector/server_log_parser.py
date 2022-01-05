from __future__ import annotations

import json
import logging
from pathlib import Path
import re
from typing import Optional

import common
from common import MappedDbData
from db_adapter import Db

log = logging.getLogger(__name__)


def parse_log_line(line: str) -> Optional[dict]:
    match = re.match(r'Request: (.*) processed in ([\.\d]+)(.*)', line)
    if not match:
        return None

    try:
        request = json.loads(match[1])
    except json.JSONDecodeError:
        log.info(f' | [REJECTED FROM PARSING]={match[0]}')
        return None

    if request['method'] == 'call':
        if isinstance(request['params'], list):
            api = request['params'][0]
            method = request['params'][1]
            params = '' if len(request['params']) == 2 else request['params'][2]
        else:
            api = request['params']['api']
            method = request['params']['method']
            params = request['params']['params']
    else:
        api, method = request['method'].split('.')
        params = request['params']

    params_str = json.dumps(params)
    total_time_int = round(float(match[2]) * 10 ** 3) if match[3] == 's' else round(float(match[2]))
    unit = 'ms' if match[3] == 's' else 'unknown'

    return {'caller': api, 'method': method, 'params': params_str, 'value': total_time_int, 'unit': unit}


def parse_and_map_log_lines(lines: list[str]) -> list[MappedDbData]:
    return [MappedDbData(**parsed) for line in lines if (parsed := parse_log_line(line))]


async def main(db: Db, file: Path, benchmark_id: int):
    log_lines = common.get_lines_from_log_file(file)
    mapped_instances = parse_and_map_log_lines(log_lines)

    common.distinguish_objects_having_same_hash(mapped_instances)

    for mapped in mapped_instances:
        await mapped.insert(db, benchmark_id)

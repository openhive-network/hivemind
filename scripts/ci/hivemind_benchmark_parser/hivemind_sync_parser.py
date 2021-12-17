from __future__ import annotations

import dataclasses
from enum import Enum
import json
import logging
import re
from typing import ClassVar, Union

import common
from db_adapter import Db

log = logging.getLogger(__name__)


class InfoType(Enum):
    CREATING_INDEXES = 'creating_indexes'
    BLOCKS_INFO = 'blocks_info'
    FILLING_DATA = 'filling_data'


@dataclasses.dataclass
class ParsedBlockInfo:
    range_from: int
    current_block: int
    last_block_number: ClassVar[int] = 1
    processing_n_blocks_time: float
    processing_total_time: float
    physical_memory: float
    virtual_memory: float
    shared_memory: float
    unit: str

    def __post_init__(self):
        self.__class__.last_block_number = self.current_block + 1


@dataclasses.dataclass
class ParsedDatabaseOperation:
    @dataclasses.dataclass
    class Partial:
        table_name: str
        total_time: float

        def __post_init__(self):
            self.params = json.dumps({"table_name": self.table_name})

    type: InfoType
    total_time: float
    partials: list[Partial]
    caller: str = 'hive_utils'
    params: str = ''


def get_interesting_log_strings_dict(text: str) -> dict[InfoType, list]:
    interesting_log_strings = {}
    creating_indexes_regex = r'INFO - hive\.utils\.stats - Total creating indexes time\n((?:.*seconds\n)*.*\n.*)'
    block_info_regex = r'.*\nINFO - hive\.indexer\.sync - \[INITIAL SYNC\] .*\n(?:.*\n){2}.*'
    filling_data_regex = r'INFO - hive\.utils\.stats - Total final operations time\n((?:.*seconds\n)*.*\n.*)'

    interesting_log_strings[InfoType.CREATING_INDEXES] = re.findall(creating_indexes_regex, text)
    interesting_log_strings[InfoType.BLOCKS_INFO] = re.findall(block_info_regex, text)
    interesting_log_strings[InfoType.FILLING_DATA] = re.findall(filling_data_regex, text)
    return interesting_log_strings


def parse_database_operation(lines: list[str], type: InfoType) -> ParsedDatabaseOperation:
    partial_regex = r'INFO - hive.utils.stats - `(.*)`: Processed final operations in ([\.\d]*) seconds'
    summary_regex = r'INFO - hive.db.db_state - Elapsed time: ([\.\d]*)s. Calculated elapsed time: [\.\d]*s. ' \
                    r'Difference: [-\.\d]*s'

    partials = []
    for line in lines:
        if match := re.match(partial_regex, line):
            partials.append(ParsedDatabaseOperation.Partial(table_name=match[1], total_time=float(match[2])))
        elif match := re.match(summary_regex, line):
            return ParsedDatabaseOperation(type=type,
                                           total_time=float(match[1]),
                                           partials=partials,
                                           )


def parse_blocks_info(lines: list[str]) -> ParsedBlockInfo:
    current_block = processing_n_blocks_time = processing_total_time = physical_memory = virtual_memory \
        = shared_memory = unit = ''

    processing_n_blocks_regex = r'INFO - hive\.indexer\.blocks - \[PROCESS MULTI\] (\d*) blocks in ([\.\d]*)s'
    current_block_regex = r'INFO - hive\.indexer\.sync - \[INITIAL SYNC\] Got block (\d*) .*'
    processing_total_time_regex = r'INFO - hive\.indexer\.sync - \[INITIAL SYNC\] Time elapsed: ([\.\d]*)s'
    memory_usage_regex = r'INFO - hive\.indexer\.sync - memory usage report: physical_memory = ([\.\d]*) (.*),' \
                         r' virtual_memory = ([\.\d]*) (.*), shared_memory = ([\.\d]*) (.*)'

    for line in lines:
        if match := re.match(current_block_regex, line):
            current_block = match[1]
        elif match := re.match(processing_n_blocks_regex, line):
            processing_n_blocks_time = match[2]
        elif match := re.match(processing_total_time_regex, line):
            processing_total_time = match[1]
        elif match := re.match(memory_usage_regex, line):
            physical_memory = match[1]
            virtual_memory = match[3]
            shared_memory = match[5]
            unit = match[2] if match[2] == match[4] == match[6] else 'unknown'

    return ParsedBlockInfo(range_from=ParsedBlockInfo.last_block_number,
                           current_block=int(current_block),
                           processing_n_blocks_time=float(processing_n_blocks_time),
                           processing_total_time=float(processing_total_time),
                           physical_memory=float(physical_memory),
                           virtual_memory=float(virtual_memory),
                           shared_memory=float(shared_memory),
                           unit=unit,
                           )


def map_interesting_log_strings_to_objects(type: InfoType,
                                           interesting_log_strings: list[str]) -> Union[None,
                                                                                        list[ParsedDatabaseOperation],
                                                                                        list[ParsedBlockInfo]]:
    if type in (InfoType.CREATING_INDEXES, InfoType.FILLING_DATA):
        return [parse_database_operation(text.split('\n'), type) for text in interesting_log_strings]
    elif type == InfoType.BLOCKS_INFO:
        return [parse_blocks_info(text.split('\n')) for text in interesting_log_strings]

    return None


async def insert_partials_for_db_operation(db: Db, p: ParsedDatabaseOperation) -> list[str]:
    caller = p.caller
    method = f'partial_{p.type.value}'

    partial_testcase_pks = []
    for partial in p.partials:
        params = partial.params
        pk = str(await common.insert_row_with_returning(db=db,
                                                        table='public.testcase',
                                                        cols_args={
                                                            'hash': common.calculate_hash(caller, method, params),
                                                            'caller': caller,
                                                            'method': method,
                                                            'params': params,
                                                        },
                                                        additional=' ON CONFLICT (hash) DO UPDATE '
                                                                   'SET caller = public.testcase.caller RETURNING hash;'
                                                        ))
        partial_testcase_pks.append(pk)
    return partial_testcase_pks


async def insert_parsed_db_operation(db: Db, p: ParsedDatabaseOperation) -> tuple[str, list[str]]:
    caller = p.caller
    method = f'{p.type.value}_total_elapsed_time'
    params = p.params

    summary_testcase_pk = \
        str(await common.insert_row_with_returning(db=db,
                                                   table='public.testcase',
                                                   cols_args={'hash': common.calculate_hash(caller, method, params),
                                                              'caller': caller,
                                                              'method': method,
                                                              'params': params,
                                                              },
                                                   additional=' ON CONFLICT (hash) DO UPDATE '
                                                              'SET caller = public.testcase.caller RETURNING hash;'))

    return summary_testcase_pk, await insert_partials_for_db_operation(db, p)


async def main(file, db, benchmark_id):
    text = common.get_text_from_log_file(file)

    # extracts only the fragments containing the necessary operations (creating indexes, filling data, block info)
    interesting_log_strings_dict = get_interesting_log_strings_dict(text)

    parsed_objects = {}  # InfoType: []
    for type, text in list(interesting_log_strings_dict.items()):
        parsed_objects[type] = map_interesting_log_strings_to_objects(type, text)

    test = 0  # TODO

    for id, p in enumerate(parsed_objects[InfoType.CREATING_INDEXES]):
        test += 1
        summary_hash, partial_hashes = await insert_parsed_db_operation(db, p)

        execution_time_ms = round(parsed_objects[InfoType.CREATING_INDEXES][id].total_time * 10 ** 3)
        await common.insert_row(db=db,
                                table='public.benchmark_values',
                                cols_args={'benchmark_description_id': benchmark_id,
                                           'testcase_hash': summary_hash,
                                           'occurrence_number': test,  # TODO
                                           'value': execution_time_ms,
                                           'unit': 'ms'},
                                )

        for partial_id, partial_hash in enumerate(partial_hashes):
            partial_object = parsed_objects[InfoType.CREATING_INDEXES][id].partials[partial_id]
            execution_time_ms = round(partial_object.total_time * 10 ** 3)
            await common.insert_row(db=db,
                                    table='public.benchmark_values',
                                    cols_args={'benchmark_description_id': benchmark_id,
                                               'testcase_hash': partial_hash,
                                               'occurrence_number': test,  # TODO
                                               'value': execution_time_ms,
                                               'unit': 'ms'},
                                    )

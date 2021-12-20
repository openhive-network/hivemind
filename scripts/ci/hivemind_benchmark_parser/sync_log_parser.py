from __future__ import annotations

import dataclasses
from enum import Enum
import json
from pathlib import Path
import re
from typing import ClassVar, Final, Optional, Union

import common
from common import MappedDbData

HIVEMIND_INDEXER: Final = 'hivemind_indexer'


class InfoType(Enum):
    CREATING_INDEXES = 'creating_indexes'
    BLOCKS_INFO = 'blocks_info'
    FILLING_DATA = 'filling_data'


CREATING_INDEXES: InfoType = InfoType.CREATING_INDEXES
BLOCKS_INFO: InfoType = InfoType.BLOCKS_INFO
FILLING_DATA: InfoType = InfoType.FILLING_DATA


@dataclasses.dataclass
class ParsedBlockIndexerInfo:
    last_block_number: ClassVar[int] = 1
    range_from: int
    range_to: int
    processing_n_blocks_time: float
    processing_total_time: float
    physical_memory: float
    virtual_memory: float
    shared_memory: float
    mem_unit: str
    time_unit: str = 'ms'
    caller: str = HIVEMIND_INDEXER

    def __post_init__(self):
        self.__class__.last_block_number = self.range_to + 1

    def to_mapped_db_data_instances(self) -> list[MappedDbData]:
        return [MappedDbData(**self.processing_blocks_partial_time()),
                MappedDbData(**self.processing_blocks_total_elapsed_time()),
                MappedDbData(**self.memory_usage_physical()),
                MappedDbData(**self.memory_usage_virtual()),
                MappedDbData(**self.memory_usage_shared()),
                ]

    def processing_blocks_partial_time(self) -> dict:
        return {'caller': self.caller,
                'method': 'processing_blocks_partial_time',
                'params': json.dumps({"from": self.range_from, "to": self.range_to}),
                'value': round(self.processing_n_blocks_time * 10 ** 3),
                'unit': self.time_unit,
                }

    def processing_blocks_total_elapsed_time(self) -> dict:
        return {'caller': self.caller,
                'method': 'processing_blocks_total_elapsed_time',
                'params': json.dumps({"block": self.range_to}),
                'value': round(self.processing_total_time * 10 ** 3),
                'unit': self.time_unit,
                }

    def memory_usage_physical(self) -> dict:
        return {'caller': self.caller,
                'method': 'memory_usage_physical',
                'params': json.dumps({"block": self.range_to}),
                'value': round(self.physical_memory),
                'unit': self.mem_unit,
                }

    def memory_usage_virtual(self) -> dict:
        return {'caller': self.caller,
                'method': 'memory_usage_virtual',
                'params': json.dumps({"block": self.range_to}),
                'value': round(self.virtual_memory),
                'unit': self.mem_unit,
                }

    def memory_usage_shared(self) -> dict:
        return {'caller': self.caller,
                'method': 'memory_usage_shared',
                'params': json.dumps({"block": self.range_to}),
                'value': round(self.shared_memory),
                'unit': self.mem_unit,
                }


@dataclasses.dataclass
class ParsedSummaryDbOperation:
    info_type: InfoType
    total_time: float
    partials: list[ParsedPartialDbOperation]
    caller: str = HIVEMIND_INDEXER
    time_unit: str = 'ms'

    def to_mapped_db_data_instances(self) -> list[MappedDbData]:
        return [MappedDbData(**self.type_total_elapsed_time())]

    def type_total_elapsed_time(self) -> dict:
        return {'caller': self.caller,
                'method': f'{self.info_type.value}_total_elapsed_time',
                'params': '',
                'value': round(self.total_time * 10 ** 3),
                'unit': self.time_unit,
                }


@dataclasses.dataclass
class ParsedPartialDbOperation:
    info_type: InfoType
    table_name: str
    total_time: float
    caller: str = HIVEMIND_INDEXER
    time_unit: str = 'ms'

    def to_mapped_db_data_instances(self) -> list[MappedDbData]:
        return [MappedDbData(**self.type_partial_time())]

    def type_partial_time(self) -> dict:
        return {'caller': self.caller,
                'method': f'{self.info_type.value}_partial_time',
                'params': json.dumps({"table_name": self.table_name}),
                'value': round(self.total_time * 10 ** 3),
                'unit': self.time_unit,
                }


def extract_interesting_log_strings(text: str) -> dict[InfoType, list]:
    """Extracts only the fragments containing the necessary operations (creating indexes, filling data, block info)"""
    creating_indexes_regex = r'INFO - hive\.utils\.stats - Total creating indexes time\n((?:.*seconds\n)*.*\n.*)'
    block_info_regex = r'.*\nINFO - hive\.indexer\.sync - \[INITIAL SYNC\] .*\n(?:.*\n){2}.*'
    filling_data_regex = r'INFO - hive\.utils\.stats - Total final operations time\n((?:.*seconds\n)*.*\n.*)'

    return {CREATING_INDEXES: re.findall(creating_indexes_regex, text),
            BLOCKS_INFO: re.findall(block_info_regex, text),
            FILLING_DATA: re.findall(filling_data_regex, text),
            }


def parse_database_operation(lines: list[str], info_type: InfoType) -> Optional[ParsedSummaryDbOperation]:
    """Parses lines about `creating indexes` or `filling data`"""
    partial_regex = r'INFO - hive.utils.stats - `(.*)`: Processed final operations in ([\.\d]*) seconds'
    summary_regex = r'INFO - hive.db.db_state - Elapsed time: ([\.\d]*)s. Calculated elapsed time: [\.\d]*s. ' \
                    r'Difference: [-\.\d]*s'

    partials = []
    for line in lines:
        if match := re.match(partial_regex, line):
            partials.append(ParsedPartialDbOperation(info_type=info_type,
                                                     table_name=match[1],
                                                     total_time=float(match[2]),
                                                     ))
        elif match := re.match(summary_regex, line):
            return ParsedSummaryDbOperation(info_type=info_type,
                                            total_time=float(match[1]),
                                            partials=partials,
                                            )
    return None


def parse_blocks_info(lines: list[str]) -> Optional[ParsedBlockIndexerInfo]:
    """Parses lines about `blocks info`"""
    current_block = processing_n_blocks_time = processing_total_time = physical_memory = virtual_memory \
        = shared_memory = mem_unit = None

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
            mem_unit = match[2] if match[2] == match[4] == match[6] else 'unknown'

    if None in (current_block, processing_n_blocks_time, processing_total_time, physical_memory,
                virtual_memory, shared_memory, mem_unit):
        return None

    return ParsedBlockIndexerInfo(range_from=ParsedBlockIndexerInfo.last_block_number,
                                  range_to=int(current_block),
                                  processing_n_blocks_time=float(processing_n_blocks_time),
                                  processing_total_time=float(processing_total_time),
                                  physical_memory=float(physical_memory),
                                  virtual_memory=float(virtual_memory),
                                  shared_memory=float(shared_memory),
                                  mem_unit=mem_unit,
                                  )


def parse_log_strings_to_objects(info_type: InfoType,
                                 interesting_log_strings: list[str]
                                 ) -> Union[list[ParsedSummaryDbOperation], list[ParsedBlockIndexerInfo]]:
    if info_type in (CREATING_INDEXES, FILLING_DATA):
        return [parsed for text in interesting_log_strings if
                (parsed := parse_database_operation(text.split('\n'), info_type)) is not None]
    elif info_type == BLOCKS_INFO:
        return [parsed for text in interesting_log_strings if
                (parsed := parse_blocks_info(text.split('\n'))) is not None]
    return []


async def main(db, file: Path, benchmark_id: int):
    text = common.get_text_from_log_file(file)
    interesting_log_strings = extract_interesting_log_strings(text)

    parsed_objects = {}
    for info_type, text in list(interesting_log_strings.items()):
        parsed_objects[info_type] = parse_log_strings_to_objects(info_type, text)

    all_parsed_objects = []
    for info_type, parsed_list in parsed_objects.items():
        for parsed in parsed_list:
            if info_type in (CREATING_INDEXES, FILLING_DATA):
                all_parsed_objects.extend(parsed.partials)
            all_parsed_objects.append(parsed)

    mapped_instances = []
    for parsed in all_parsed_objects:
        mapped_instances.extend(parsed.to_mapped_db_data_instances())

    common.distinguish_objects_having_same_hash(mapped_instances)

    for mapped in mapped_instances:
        await mapped.insert(db, benchmark_id)

from __future__ import annotations

import dataclasses
from enum import Enum
import json
from pathlib import Path
from typing import Final, Union

import common
from common import MappedDbData
from db_adapter import Db

REPLAY_BENCHMARK: Final = 'replay_benchmark'


class MeasurementType(Enum):
    PARTIAL = 'partial_measurement'
    TOTAL = 'total_measurement'


PARTIAL: MeasurementType = MeasurementType.PARTIAL
TOTAL: MeasurementType = MeasurementType.TOTAL


@dataclasses.dataclass
class ParsedMeasurement:
    measurement_type: MeasurementType
    block_number: int
    real_ms: int
    cpu_ms: int
    current_mem: int
    peak_mem: int
    caller: str = REPLAY_BENCHMARK
    time_unit: str = 'ms'
    mem_unit: str = 'kB'

    def to_mapped_db_data_instances(self) -> list[MappedDbData]:
        return [MappedDbData(**self.type_real_time()),
                MappedDbData(**self.type_cpu_time()),
                MappedDbData(**self.type_current_memory_usage()),
                MappedDbData(**self.type_peak_memory_usage()),
                ]

    def type_real_time(self):
        return {'caller': self.caller,
                'method': f'{self.measurement_type.value}_real_time',
                'params': json.dumps({"block": self.block_number}),
                'value': self.real_ms,
                'unit': self.time_unit,
                }

    def type_cpu_time(self):
        return {'caller': self.caller,
                'method': f'{self.measurement_type.value}_cpu_time',
                'params': json.dumps({"block": self.block_number}),
                'value': self.cpu_ms,
                'unit': self.time_unit,
                }

    def type_current_memory_usage(self):
        return {'caller': self.caller,
                'method': f'{self.measurement_type.value}_current_memory_usage',
                'params': json.dumps({"block": self.block_number}),
                'value': self.current_mem,
                'unit': self.mem_unit,
                }

    def type_peak_memory_usage(self):
        return {'caller': self.caller,
                'method': f'{self.measurement_type.value}_peak_memory_usage',
                'params': json.dumps({"block": self.block_number}),
                'value': self.peak_mem,
                'unit': self.mem_unit,
                }


def remove_unused_key(var: Union[list[dict], dict], key: str) -> None:
    if isinstance(var, list):
        [v.pop(key) for v in var]
    if isinstance(var, dict):
        var.pop(key)


async def main(db: Db, file: Path, benchmark_id):
    text = common.get_text_from_log_file(file)
    replay = json.loads(text)
    measurements = replay['measurements']
    total_measurement = replay['total_measurement']

    unused_key = 'index_memory_details_cntr'
    remove_unused_key(measurements, unused_key)
    remove_unused_key(total_measurement, unused_key)

    parsed_measurements = [ParsedMeasurement(measurement_type=PARTIAL, **m) for m in measurements]
    parsed_measurements.append(ParsedMeasurement(measurement_type=TOTAL, **total_measurement))

    mapped_instances = []
    for parsed in parsed_measurements:
        mapped_instances.extend(parsed.to_mapped_db_data_instances())

    common.distinguish_objects_having_same_hash(mapped_instances)

    for mapped in mapped_instances:
        await mapped.insert(db, benchmark_id)

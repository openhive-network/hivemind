import datetime
from pathlib import Path
import socket
from typing import Final

import pytest

from constants import ROOT_PATH
from db_adapter import Db
import main
import replay_benchmark_parser as parser

SAMPLE_JSON: Final = ROOT_PATH / 'tests/mock_data/replay_benchmark_parser' \
                                 '/sample.json'


@pytest.mark.asyncio
async def test_replay_benchmark_mode(db: Db, sql_select_all: str):
    sys_argv = ['-m', '1',
                '-f', str(SAMPLE_JSON),
                '-db', '',
                '--desc', 'replay benchmark parser functional test',
                '--exec-env-desc', 'mock db',
                '--server-name', 'localhost',
                '--app-version', '1.0',
                '--testsuite-version', '2.0',
                ]

    args = main.init_argparse(sys_argv)
    timestamp = datetime.datetime.now()

    benchmark_id = await main.insert_benchmark_description(db, args=args, timestamp=timestamp)

    await parser.main(db, file=Path(args.file), benchmark_id=benchmark_id)

    actual = await db.query_all(sql_select_all)

    benchmark = ('replay benchmark parser functional test', 'mock db', timestamp.replace(microsecond=0), 'localhost',
                 '1.0', '2.0', socket.gethostname())

    partial_measurement_real_time1 = ('replay_benchmark', 'partial_measurement_real_time',
                                      '{"block": 5000000}',
                                      'e78f8ecc6432e114d7df40ef4653779e2df3234bb7b5162026839faa60e0b7cf',)

    partial_measurement_cpu_time1 = ('replay_benchmark', 'partial_measurement_cpu_time',
                                     '{"block": 5000000}',
                                     '9ee0219ef6e98f9fb77bd8017d90415c650a8045673da580c966170c86a755ad')

    partial_measurement_current_memory_usage1 = ('replay_benchmark', 'partial_measurement_current_memory_usage',
                                                 '{"block": 5000000}',
                                                 'cc86151815a548cce9dbe2b32b69814a40960ac18dc8a8f9d682c36813fd7964')

    partial_measurement_peak_memory_usage1 = ('replay_benchmark', 'partial_measurement_peak_memory_usage',
                                              '{"block": 5000000}',
                                              'b2be1ba79145280ddbc372059fc96fe0b1967fe38b26f9e879934df3707d0086')

    partial_measurement_real_time2 = ('replay_benchmark', 'partial_measurement_real_time',
                                      '{"block": 100000}',
                                      'dce238987d8e39aec85ab197d65c9c4052216d5f28a12c1bf8b53dca424e9cda')

    partial_measurement_cpu_time2 = ('replay_benchmark', 'partial_measurement_cpu_time',
                                     '{"block": 100000}',
                                     '2298044de9c07dba20c52e00082b1cf952504196f4de5e9efa55c01ba0e714bc')

    partial_measurement_current_memory_usage2 = ('replay_benchmark', 'partial_measurement_current_memory_usage',
                                                 '{"block": 100000}',
                                                 'f000a42c4ea389889271a92098ddf6c803576da969f21c293f35a4388cb872a7')

    partial_measurement_peak_memory_usage2 = ('replay_benchmark', 'partial_measurement_peak_memory_usage',
                                              '{"block": 100000}',
                                              'b5db1b2ef42569610bfdb85f14d07f898ba84bbb3555e6ea8280d8b212352e92')

    partial_measurement_real_time3 = ('replay_benchmark', 'total_measurement_real_time',
                                      '{"block": 5000000}',
                                      '66c7db47039a0f20befd699609d50416141e3cce1539baf014419128483631e4')

    partial_measurement_cpu_time3 = ('replay_benchmark', 'total_measurement_cpu_time',
                                     '{"block": 5000000}',
                                     '3a6cf92ea1bf7f393b8032081b77401020043408fe8583f0e0687fa8681ddecb')

    partial_measurement_current_memory_usage3 = ('replay_benchmark', 'total_measurement_current_memory_usage',
                                                 '{"block": 5000000}',
                                                 'c008a5dc57dfa796dc00ef410235f91f780cc5cec5fe38f1cdb0e13e3b1f140d')

    partial_measurement_peak_memory_usage3 = ('replay_benchmark', 'total_measurement_peak_memory_usage',
                                              '{"block": 5000000}',
                                              '531550150b907e96d74110fb20d23d06eb568b8435cb190e80262544ed9a183e',)

    assert actual == [(*benchmark, *partial_measurement_real_time1, 0, 'ms'),
                      (*benchmark, *partial_measurement_cpu_time1, 0, 'ms'),
                      (*benchmark, *partial_measurement_current_memory_usage1, 6801740, 'MB'),
                      (*benchmark, *partial_measurement_peak_memory_usage1, 6801740, 'MB'),

                      (*benchmark, *partial_measurement_real_time2, 1138, 'ms'),
                      (*benchmark, *partial_measurement_cpu_time2, 1135, 'ms'),
                      (*benchmark, *partial_measurement_current_memory_usage2, 6867456, 'MB'),
                      (*benchmark, *partial_measurement_peak_memory_usage2, 6900240, 'MB'),

                      (*benchmark, *partial_measurement_real_time3, 877896, 'ms'),
                      (*benchmark, *partial_measurement_cpu_time3, 560396, 'ms'),
                      (*benchmark, *partial_measurement_current_memory_usage3, 7183280, 'MB'),
                      (*benchmark, *partial_measurement_peak_memory_usage3, 7183280, 'MB'),
                      ]

import datetime
from pathlib import Path
import socket
from typing import Final

import pytest

from constants import ROOT_PATH
from db_adapter import Db
import main
import sync_log_parser as parser

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/sync_log_parser' \
                                                 '/sample_with_mixed_lines.log'


@pytest.mark.asyncio
async def test_sync_log_mode(db: Db, sql_select_all: str):
    sys_argv = ['-m', '2',
                '-f', str(SAMPLE_LOG_WITH_MIXED_LINES),
                '-db', '',
                '--desc', 'sync parser functional test',
                '--exec-env-desc', 'mock db',
                '--server-name', 'localhost',
                '--app-version', '1.0',
                '--testsuite-version', '2.0',
                ]

    args = main.init_argparse(sys_argv)
    timestamp = datetime.datetime.now()

    benchmark_id = await main.insert_benchmark_description(db, args=args, timestamp=timestamp)

    await parser.main(db, file=Path(args.file), benchmark_id=benchmark_id)
    parser.ParsedBlockIndexerInfo.last_block_number = 1  # cleanup

    actual = await db.query_all(sql_select_all)

    benchmark = ('sync parser functional test', 'mock db', timestamp.replace(microsecond=0), 'localhost',
                 '1.0', '2.0', socket.gethostname())

    creating_indexes_partial_time1 = ('hivemind_indexer', 'creating_indexes_partial_time',
                                      '{"table_name": "hive_posts"}',
                                      '580ddbd738eefe205c29dd2a1e6d5f4ffd18d8c4a57db552650b7d5c7b103361')

    creating_indexes_partial_time2 = ('hivemind_indexer', 'creating_indexes_partial_time',
                                      '{"table_name": "hive_votes"}',
                                      '6782e273be44a67fda126f44fb637dd95ca9385cc22d9ea1ddebc2b39572756c')

    filling_data_partial_time1 = ('hivemind_indexer', 'filling_data_partial_time',
                                  '{"table_name": "hive_posts"}',
                                  'd9b4cca50b2798baaea545f4e0112cf4c918d4ec4f65f959e55ac8d794f011e2')

    filling_data_partial_time2 = ('hivemind_indexer', 'filling_data_partial_time',
                                  '{"table_name": "blocks_consistency_flag"}',
                                  '711c42c7ceff45defbbfeceaf2886f0f94508a9c76a9c4493bb6aa1162115b66')

    creating_indexes_total_elapsed_time = ('hivemind_indexer', 'creating_indexes_total_elapsed_time',
                                           '',
                                           '5e1bab6e528eff6b671849627606a9b97536732ad5d73110420dcc3418a40551')

    processing_blocks_partial_time1 = ('hivemind_indexer', 'processing_blocks_partial_time',
                                       '{"from": 1, "to": 1000}',
                                       '799820c6808f0d68aee35ba45fa2970d0accae49021d915df806253563002764')

    processing_blocks_total_elapsed_time1 = ('hivemind_indexer', 'processing_blocks_total_elapsed_time',
                                             '{"block": 1000}',
                                             '1077e9a1c493b5928868626b4df05a2ef82cfe4ac6e62f58997984d5b3664a2e')

    memory_usage_physical1 = ('hivemind_indexer', 'memory_usage_physical',
                              '{"block": 1000}',
                              '8af014fa839affbd6929f465cfe48582d7057ba48042b5262a3d678ada6541f3')

    memory_usage_virtual1 = ('hivemind_indexer', 'memory_usage_virtual',
                             '{"block": 1000}',
                             'c8d043c5fcf62ccca40ea8a01239a780c1b12dd5680db49da73ebe6d04e204d9')

    memory_usage_shared1 = ('hivemind_indexer', 'memory_usage_shared',
                            '{"block": 1000}',
                            '6d8dceae83485a205054257774666282d24b53345cfbc6785ff5029c712df22f')

    processing_blocks_partial_time2 = ('hivemind_indexer', 'processing_blocks_partial_time',
                                       '{"from": 1001, "to": 4000}',
                                       'ca842d5810739d36d1db8bca82bbaf55aea00d1b60e9acf3120e47c08ac14aea')

    processing_blocks_total_elapsed_time2 = ('hivemind_indexer', 'processing_blocks_total_elapsed_time',
                                             '{"block": 4000}',
                                             'fb8dff4844e6c6f80b2f6c11676f49de94695a21a4aaba3405c107b7cae580c1')

    memory_usage_physical2 = ('hivemind_indexer', 'memory_usage_physical',
                              '{"block": 4000}',
                              '766e38bbbeb5ecde19e9fdba5f5115a2f1f06fe932a35ab0d22f3e3dbdbbc8a0')

    memory_usage_virtual2 = ('hivemind_indexer', 'memory_usage_virtual',
                             '{"block": 4000}',
                             '59a33d8e30f364ff1bab5c8d8c1d9d3c9acce327b4384e4beaa6370d08004868')

    memory_usage_shared2 = ('hivemind_indexer', 'memory_usage_shared',
                            '{"block": 4000}',
                            '25fbf6f01b1e70c097117b482203f1befb099f0f66b0eb0b5b2d4371f3802487')

    processing_blocks_partial_time3 = ('hivemind_indexer', 'processing_blocks_partial_time',
                                       '{"from": 4001, "to": 4970}',
                                       'a0162f8d4504d3b1536d265e6d87ceaf88dc2a2d5aaa4af239ed8df15988f221')

    processing_blocks_total_elapsed_time3 = ('hivemind_indexer', 'processing_blocks_total_elapsed_time',
                                             '{"block": 4970}',
                                             '5973bd268c81196c48990df01a922e88017cc8423b9f89c3779d8a263652254c')
    memory_usage_physical3 = ('hivemind_indexer', 'memory_usage_physical',
                              '{"block": 4970}',
                              'c1c75688156e75cdd15a5ffc56a41668d21ce61870b65bddc70102ce1953b5c1')

    memory_usage_virtual3 = ('hivemind_indexer', 'memory_usage_virtual',
                             '{"block": 4970}',
                             '1d1d248211691368aa441a64ff6ad77b2709ab2af9e94d74f6edb27a60fd7165')

    memory_usage_shared3 = ('hivemind_indexer', 'memory_usage_shared',
                            '{"block": 4970}',
                            '16c0bc86c3753da8fd2acf6cea2b3a04efc98b6bd009789b84e28bc634dac3fd')

    filling_data_total_elapsed_time = ('hivemind_indexer', 'filling_data_total_elapsed_time',
                                       '',
                                       '12774917a0f1b79fced481772cb2797f379d60e80d819dd44b84e0747e0f3f97')

    assert actual == [(*benchmark, *creating_indexes_partial_time1, 85, 'ms'),
                      (*benchmark, *creating_indexes_partial_time2, 40, 'ms'),
                      (*benchmark, *creating_indexes_partial_time1, 2085, 'ms'),
                      (*benchmark, *creating_indexes_partial_time2, 2040, 'ms'),
                      (*benchmark, *filling_data_partial_time1, 132959, 'ms'),
                      (*benchmark, *filling_data_partial_time2, 125678, 'ms'),

                      (*benchmark, *creating_indexes_total_elapsed_time, 100, 'ms'),
                      (*benchmark, *creating_indexes_total_elapsed_time, 4100, 'ms'),

                      (*benchmark, *processing_blocks_partial_time1, 56, 'ms'),
                      (*benchmark, *processing_blocks_total_elapsed_time1, 169, 'ms'),
                      (*benchmark, *memory_usage_physical1, 62, 'MB'),
                      (*benchmark, *memory_usage_virtual1, 1954, 'MB'),
                      (*benchmark, *memory_usage_shared1, 14, 'MB'),

                      (*benchmark, *processing_blocks_partial_time2, 310, 'ms'),
                      (*benchmark, *processing_blocks_total_elapsed_time2, 620, 'ms'),
                      (*benchmark, *memory_usage_physical2, 65, 'MB'),
                      (*benchmark, *memory_usage_virtual2, 1928, 'MB'),
                      (*benchmark, *memory_usage_shared2, 15, 'MB'),

                      (*benchmark, *processing_blocks_partial_time3, 251, 'ms'),
                      (*benchmark, *processing_blocks_total_elapsed_time3, 464, 'ms'),
                      (*benchmark, *memory_usage_physical3, 66, 'MB'),
                      (*benchmark, *memory_usage_virtual3, 1958, 'MB'),
                      (*benchmark, *memory_usage_shared3, 14, 'MB'),

                      (*benchmark, *filling_data_total_elapsed_time, 164794, 'ms'),
                      ]

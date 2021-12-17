from __future__ import annotations

from typing import Final

import pytest

import common
from constants import ROOT_PATH
from hivemind_sync_parser import InfoType
import hivemind_sync_parser as p

HIVEMIND_SYNC: Final = ROOT_PATH / 'tests/mock_data/hivemind_sync_parser' \
                                   '/hivemind-sync.log'

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/hivemind_sync_parser' \
                                                 '/sample_with_mixed_lines.log'


@pytest.fixture
def interesting_log_strings():
    text = common.get_text_from_log_file(SAMPLE_LOG_WITH_MIXED_LINES)
    return p.get_interesting_log_strings_dict(text)


def test_sync_log_getting_interesting_log_strings(interesting_log_strings):
    assert interesting_log_strings[InfoType.CREATING_INDEXES] == \
           ["""INFO - hive.utils.stats - `hive_posts`: Processed final operations in 0.0853 seconds
INFO - hive.utils.stats - `hive_votes`: Processed final operations in 0.0396 seconds
INFO - hive.utils.stats - Current final processing time: 0.3676s.
INFO - hive.db.db_state - Elapsed time: 0.1003s. Calculated elapsed time: 0.3676s. Difference: -0.2673s"""]

    assert interesting_log_strings[InfoType.BLOCKS_INFO] == \
           ["""INFO - hive.indexer.blocks - [PROCESS MULTI] 1000 blocks in 0.0557s
INFO - hive.indexer.sync - [INITIAL SYNC] Got block 1000 @ 2016-03-24T16:55:30 (17854/s, 17855rps, 331197354wps) -- eta 04m 39s
INFO - hive.indexer.sync - [INITIAL SYNC] Time elapsed: 0.169300s
INFO - hive.indexer.sync - [INITIAL SYNC] Current system time: 15:06:49
INFO - hive.indexer.sync - memory usage report: physical_memory = 61.69 MB, virtual_memory = 1953.77 MB, shared_memory = 13.53 MB""",

            """INFO - hive.indexer.blocks - [PROCESS MULTI] 3000 blocks in 0.31s
INFO - hive.indexer.sync - [INITIAL SYNC] Got block 4000 @ 2016-03-24T17:45:45 (3980/s, 3980rps, 462819751wps) -- eta 20m 55s
INFO - hive.indexer.sync - [INITIAL SYNC] Time elapsed: 0.62s
INFO - hive.indexer.sync - [INITIAL SYNC] Current system time: 15:06:50
INFO - hive.indexer.sync - memory usage report: physical_memory = 64.82 MB, virtual_memory = 1927.85 MB, shared_memory = 14.53 MB""",

            """INFO - hive.indexer.blocks - [PROCESS MULTI] 970 blocks in 0.2507s
INFO - hive.indexer.sync - [INITIAL SYNC] Got block 4970 @ 2016-03-24T17:45:45 (3980/s, 3980rps, 462819751wps) -- eta 20m 55s
INFO - hive.indexer.sync - [INITIAL SYNC] Time elapsed: 0.463699s
INFO - hive.indexer.sync - [INITIAL SYNC] Current system time: 15:06:50
INFO - hive.indexer.sync - memory usage report: physical_memory = 65.82 MB, virtual_memory = 1957.85 MB, shared_memory = 13.53 MB"""]

    assert interesting_log_strings[InfoType.FILLING_DATA] == \
           ["""INFO - hive.utils.stats - `hive_posts`: Processed final operations in 132.9586 seconds
INFO - hive.utils.stats - `blocks_consistency_flag`: Processed final operations in 125.6784 seconds
INFO - hive.utils.stats - Current final processing time: 326.9432s.
INFO - hive.db.db_state - Elapsed time: 164.7935s. Calculated elapsed time: 326.9432s. Difference: -162.1497s"""]


def test_sync_log_parsing_creating_indexes(interesting_log_strings):
    map = p.map_interesting_log_strings_to_objects
    creating_indexes_objects = map(InfoType.CREATING_INDEXES, interesting_log_strings[InfoType.CREATING_INDEXES])

    creating_indexes_partials = [p.ParsedDatabaseOperation.Partial(table_name='hive_posts', total_time=0.0853),
                                 p.ParsedDatabaseOperation.Partial(table_name='hive_votes', total_time=0.0396),
                                 ]

    assert creating_indexes_objects == [p.ParsedDatabaseOperation(type=p.InfoType.CREATING_INDEXES,
                                                                  total_time=0.1003,
                                                                  partials=creating_indexes_partials),
                                        ]


def test_sync_log_parsing_filling_data(interesting_log_strings):
    map = p.map_interesting_log_strings_to_objects
    filling_data_objects = map(InfoType.FILLING_DATA, interesting_log_strings[InfoType.FILLING_DATA])

    filling_data_partials = [p.ParsedDatabaseOperation.Partial(table_name='hive_posts', total_time=132.9586),
                             p.ParsedDatabaseOperation.Partial(table_name='blocks_consistency_flag',
                                                               total_time=125.6784),
                             ]

    assert filling_data_objects == [p.ParsedDatabaseOperation(type=p.InfoType.FILLING_DATA,
                                                              total_time=164.7935,
                                                              partials=filling_data_partials,
                                                              ),
                                    ]


def test_sync_log_parsing_blocks_info(interesting_log_strings):
    map = p.map_interesting_log_strings_to_objects
    blocks_info_objects = map(InfoType.BLOCKS_INFO, interesting_log_strings[InfoType.BLOCKS_INFO])

    assert blocks_info_objects == [p.ParsedBlockInfo(range_from=1,
                                                     current_block=1000,
                                                     processing_n_blocks_time=0.0557,
                                                     processing_total_time=0.169300,
                                                     physical_memory=61.69,
                                                     virtual_memory=1953.77,
                                                     shared_memory=13.53,
                                                     unit='MB',
                                                     ),
                                   p.ParsedBlockInfo(range_from=1001,
                                                     current_block=4000,
                                                     processing_n_blocks_time=0.31,
                                                     processing_total_time=0.62,
                                                     physical_memory=64.82,
                                                     virtual_memory=1927.85,
                                                     shared_memory=14.53,
                                                     unit='MB',
                                                     ),
                                   p.ParsedBlockInfo(range_from=4001,
                                                     current_block=4970,
                                                     processing_n_blocks_time=0.2507,
                                                     processing_total_time=0.463699,
                                                     physical_memory=65.82,
                                                     virtual_memory=1957.85,
                                                     shared_memory=13.53,
                                                     unit='MB',
                                                     ),
                                   ]

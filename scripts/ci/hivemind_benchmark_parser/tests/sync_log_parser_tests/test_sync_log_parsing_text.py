from __future__ import annotations

import sync_log_parser as p

CREATING_INDEXES: p.InfoType = p.InfoType.CREATING_INDEXES
BLOCKS_INFO: p.InfoType = p.InfoType.BLOCKS_INFO
FILLING_DATA: p.InfoType = p.InfoType.FILLING_DATA


def test_sync_log_parsing_creating_indexes(interesting_sync_log_strings):
    parsed_objects = p.parse_log_strings_to_objects(CREATING_INDEXES, interesting_sync_log_strings[CREATING_INDEXES])

    partials1 = [p.ParsedPartialDbOperation(info_type=CREATING_INDEXES,
                                            table_name='hive_posts',
                                            total_time=0.0853,
                                            ),
                 p.ParsedPartialDbOperation(info_type=CREATING_INDEXES,
                                            table_name='hive_votes',
                                            total_time=0.0396,
                                            ),
                 ]

    partials2 = [p.ParsedPartialDbOperation(info_type=CREATING_INDEXES,
                                            table_name='hive_posts',
                                            total_time=2.0853,
                                            ),
                 p.ParsedPartialDbOperation(info_type=CREATING_INDEXES,
                                            table_name='hive_votes',
                                            total_time=2.0396,
                                            ),
                 ]

    assert parsed_objects == [p.ParsedSummaryDbOperation(info_type=CREATING_INDEXES,
                                                         total_time=0.1003,
                                                         partials=partials1,
                                                         ),
                              p.ParsedSummaryDbOperation(info_type=CREATING_INDEXES,
                                                         total_time=4.1003,
                                                         partials=partials2,
                                                         ),
                              ]


def test_sync_log_parsing_filling_data(interesting_sync_log_strings):
    parsed_objects = p.parse_log_strings_to_objects(FILLING_DATA, interesting_sync_log_strings[FILLING_DATA])

    partials = [p.ParsedPartialDbOperation(info_type=FILLING_DATA,
                                           table_name='hive_posts',
                                           total_time=132.9586,
                                           ),
                p.ParsedPartialDbOperation(info_type=FILLING_DATA,
                                           table_name='blocks_consistency_flag',
                                           total_time=125.6784,
                                           ),
                ]

    assert parsed_objects == [p.ParsedSummaryDbOperation(info_type=FILLING_DATA,
                                                         total_time=164.7935,
                                                         partials=partials,
                                                         ),
                              ]


def test_sync_log_parsing_blocks_info(interesting_sync_log_strings):
    parsed_objects = p.parse_log_strings_to_objects(BLOCKS_INFO, interesting_sync_log_strings[BLOCKS_INFO])

    assert parsed_objects == [p.ParsedBlockIndexerInfo(range_from=1,
                                                       range_to=1000,
                                                       processing_n_blocks_time=0.0557,
                                                       processing_total_time=0.169300,
                                                       physical_memory=61.69,
                                                       virtual_memory=1953.77,
                                                       shared_memory=13.53,
                                                       mem_unit='MB',
                                                       ),
                              p.ParsedBlockIndexerInfo(range_from=1001,
                                                       range_to=4000,
                                                       processing_n_blocks_time=0.31,
                                                       processing_total_time=0.62,
                                                       physical_memory=64.82,
                                                       virtual_memory=1927.85,
                                                       shared_memory=14.53,
                                                       mem_unit='MB',
                                                       ),
                              p.ParsedBlockIndexerInfo(range_from=4001,
                                                       range_to=4970,
                                                       processing_n_blocks_time=0.2507,
                                                       processing_total_time=0.463699,
                                                       physical_memory=65.82,
                                                       virtual_memory=1957.85,
                                                       shared_memory=13.53,
                                                       mem_unit='MB',
                                                       ),
                              ]


def test_sync_log_parsing_to_objects_wrong():
    assert p.parse_log_strings_to_objects(1, ['', 'abc']) == []
    assert p.parse_log_strings_to_objects(CREATING_INDEXES, ['', 'abc']) == []
    assert p.parse_log_strings_to_objects(FILLING_DATA, ['', 'abc']) == []
    assert p.parse_log_strings_to_objects(BLOCKS_INFO, ['', 'abc']) == []

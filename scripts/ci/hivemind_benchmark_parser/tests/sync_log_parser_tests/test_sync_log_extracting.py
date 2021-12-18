import sync_log_parser as p

CREATING_INDEXES: p.InfoType = p.InfoType.CREATING_INDEXES
BLOCKS_INFO: p.InfoType = p.InfoType.BLOCKS_INFO
FILLING_DATA: p.InfoType = p.InfoType.FILLING_DATA


def test_sync_log_extracting_interesting_log_strings(interesting_sync_log_strings):
    assert interesting_sync_log_strings[CREATING_INDEXES] == \
           ["""INFO - hive.utils.stats - `hive_posts`: Processed final operations in 0.0853 seconds
INFO - hive.utils.stats - `hive_votes`: Processed final operations in 0.0396 seconds
INFO - hive.utils.stats - Current final processing time: 0.3676s.
INFO - hive.db.db_state - Elapsed time: 0.1003s. Calculated elapsed time: 0.3676s. Difference: -0.2673s""",
            """INFO - hive.utils.stats - `hive_posts`: Processed final operations in 2.0853 seconds
INFO - hive.utils.stats - `hive_votes`: Processed final operations in 2.0396 seconds
INFO - hive.utils.stats - Current final processing time: 0.3676s.
INFO - hive.db.db_state - Elapsed time: 4.1003s. Calculated elapsed time: 0.3676s. Difference: -0.2673s"""]

    assert interesting_sync_log_strings[BLOCKS_INFO] == \
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

    assert interesting_sync_log_strings[FILLING_DATA] == \
           ["""INFO - hive.utils.stats - `hive_posts`: Processed final operations in 132.9586 seconds
INFO - hive.utils.stats - `blocks_consistency_flag`: Processed final operations in 125.6784 seconds
INFO - hive.utils.stats - Current final processing time: 326.9432s.
INFO - hive.db.db_state - Elapsed time: 164.7935s. Calculated elapsed time: 326.9432s. Difference: -162.1497s"""]


def test_sync_log_extracting_interesting_log_strings_empty():
    assert p.extract_interesting_log_strings('') == {CREATING_INDEXES: [],
                                                     BLOCKS_INFO: [],
                                                     FILLING_DATA: [],
                                                     }

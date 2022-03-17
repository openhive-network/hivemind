#!/usr/bin/env python3
from test_base import run_test

if __name__ == '__main__':
    reference_hive_node_url = 'http://127.0.0.1:8090'
    test_hive_node_url = 'http://127.0.0.1:8080'

    payload = {
        "jsonrpc": "2.0",
        "method": "database_api.list_comments",
        "params": {"start": ['steemit', 'firstpost', '', ''], "limit": 10, "order": 'by_root'},
        "id": 1,
    }

    run_test(
        reference_hive_node_url,
        test_hive_node_url,
        payload,
        ['author', 'permlink', 'root_author', 'root_permlink', 'created'],
    )

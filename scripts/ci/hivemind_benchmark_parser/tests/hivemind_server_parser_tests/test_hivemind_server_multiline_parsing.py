from typing import Final

from constants import ROOT_PATH
import hivemind_server_parser as parser

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/hivemind_server_parser' \
                                                 '/sample_with_mixed_lines.log'
SAMPLE_LOG_WITH_INVALID_LINES_ONLY: Final = ROOT_PATH / 'tests/mock_data/hivemind_server_parser' \
                                                        '/sample_with_invalid_lines_only.log'


def test_preparing_db_records_from_log_lines():
    api = 'bridge'
    expected_result = [parser.ParsedTestcase(api=api,
                                             method='get_account_posts',
                                             parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                             total_time=0.0740,
                                             id=1,
                                             ),
                       parser.ParsedTestcase(api=api,
                                             method='get_account_posts',
                                             parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                             total_time=0.0740,
                                             id=2,
                                             ),
                       parser.ParsedTestcase(api=api,
                                             method='get_account_posts',
                                             parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                             total_time=0.0740,
                                             id=3,
                                             ),
                       parser.ParsedTestcase(api=api,
                                             method='get_community',
                                             parameters='{"name": "hive-135485"}',
                                             total_time=0.0154,
                                             id=1,
                                             ),
                       parser.ParsedTestcase(api=api,
                                             method='get_account_posts',
                                             parameters='{"sort": "blog", "account": "steemit"}',
                                             total_time=0.0255,
                                             id=1,
                                             ),
                       ]

    with open(SAMPLE_LOG_WITH_MIXED_LINES, 'r') as file:
        log_lines = file.readlines()

    assert parser.prepare_db_records_from_log_lines(log_lines) == expected_result


def test_server_log_empty_lines_parsing():
    assert parser.prepare_db_records_from_log_lines(['', '', '']) == []


def test_server_log_invalid_lines_parsing():
    with open(SAMPLE_LOG_WITH_INVALID_LINES_ONLY, 'r') as file:
        log_lines = file.readlines()
    assert parser.prepare_db_records_from_log_lines(log_lines) == []

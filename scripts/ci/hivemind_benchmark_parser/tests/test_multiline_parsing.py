from config import ROOT_PATH
import parser

SAMPLE_LOG_WITH_MIXED_LINES = ROOT_PATH / 'input/sample_with_mixed_lines.txt'
SAMPLE_LOG_WITH_INVALID_LINES_ONLY = ROOT_PATH / 'input/sample_with_invalid_lines_only.txt'


def test_get_lines_from_log_file():
    log_lines = parser.get_lines_from_log_file(SAMPLE_LOG_WITH_MIXED_LINES)
    assert len(log_lines) != 0


def test_multiline_parsing():
    api = 'bridge'
    expected_result = [parser.ParsedRequest(api=api,
                                            method='get_account_posts',
                                            parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                            total_time=0.0740,
                                            id=1,
                                            ),
                       parser.ParsedRequest(api=api,
                                            method='get_account_posts',
                                            parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                            total_time=0.0740,
                                            id=2,
                                            ),
                       parser.ParsedRequest(api=api,
                                            method='get_account_posts',
                                            parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                                            total_time=0.0740,
                                            id=3,
                                            ),
                       parser.ParsedRequest(api=api,
                                            method='get_community',
                                            parameters='{"name": "hive-135485"}',
                                            total_time=0.0154,
                                            id=1,
                                            ),
                       parser.ParsedRequest(api=api,
                                            method='get_account_posts',
                                            parameters='{"sort": "blog", "account": "steemit"}',
                                            total_time=0.0255,
                                            id=1,
                                            ),
                       ]

    with open(SAMPLE_LOG_WITH_MIXED_LINES, 'r') as file:
        log_lines = file.readlines()

    assert parser.parse_log_lines(log_lines) == expected_result


def test_empty_lines_parsing():
    assert parser.parse_log_lines(['', '', '']) == []


def test_invalid_lines_parsing():
    with open(SAMPLE_LOG_WITH_INVALID_LINES_ONLY, 'r') as file:
        log_lines = file.readlines()
    assert parser.parse_log_lines(log_lines) == []

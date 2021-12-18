from typing import Final

from constants import ROOT_PATH
import server_log_parser as parser

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/server_log_parser' \
                                                 '/sample_with_mixed_lines.log'
SAMPLE_LOG_WITH_INVALID_LINES_ONLY: Final = ROOT_PATH / 'tests/mock_data/server_log_parser' \
                                                        '/sample_with_invalid_lines_only.log'


def test_server_log_parsing_and_mapping(mock_mapped_list):
    with open(SAMPLE_LOG_WITH_MIXED_LINES, 'r') as file:
        log_lines = file.readlines()
    assert parser.parse_and_map_log_lines(log_lines) == mock_mapped_list


def test_server_log_empty_lines_parsing_and_mapping():
    assert parser.parse_and_map_log_lines(['', '', '']) == []


def test_server_log_invalid_lines_parsing_and_mapping():
    with open(SAMPLE_LOG_WITH_INVALID_LINES_ONLY, 'r') as file:
        log_lines = file.readlines()
    assert parser.parse_and_map_log_lines(log_lines) == []

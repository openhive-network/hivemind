from __future__ import annotations

from typing import Final

import pytest

import common
from constants import ROOT_PATH
import main

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/hivemind_server_parser' \
                                                 '/sample_with_mixed_lines.log'


@pytest.fixture
def sample_row() -> dict[str, str]:
    return {'api': 'bridge',
            'method': 'get_account_posts',
            'parameters': '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
            'hash': '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75',
            }


def test_args_parsing():
    args = main.init_argparse(['-m', '1',
                               '-f', 'input/sample_with_mixed_lines.log',
                               '-db', 'testurl',
                               '--desc', 'Test description',
                               '--exec-env-desc', 'environment',
                               '--server-name', 'server',
                               '--app-version', '1.00',
                               '--testsuite-version', '2.00',
                               ])

    assert args.mode == 1
    assert args.file == 'input/sample_with_mixed_lines.log'
    assert args.database_url == 'testurl'
    assert args.desc == 'Test description'
    assert args.exec_env_desc == 'environment'
    assert args.server_name == 'server'
    assert args.app_version == '1.00'
    assert args.testsuite_version == '2.00'


def test_get_lines_from_log_file():
    log_lines = common.get_lines_from_log_file(SAMPLE_LOG_WITH_MIXED_LINES)
    assert len(log_lines) != 0


def test_get_text_from_log_file():
    text = common.get_lines_from_log_file(SAMPLE_LOG_WITH_MIXED_LINES)
    assert text


def test_calculating_hash(sample_row):
    text = f'{sample_row["api"]},{sample_row["method"]},{sample_row["parameters"]}'
    assert common.calculate_hash(text) == '3cb9508b3fdc131a32dd8085fd62e3718ffe03f09e031961c94f36d9b210ef84'


def test_retrieving_cols_and_params_from_dict(sample_row):
    expected_cols = 'api, method, parameters, hash'
    expected_params = ':api, :method, :parameters, :hash'
    actual = common.retrieve_cols_and_params(sample_row)

    assert actual == (expected_cols, expected_params)

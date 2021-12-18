from __future__ import annotations

from typing import Final

import pytest

import common
from constants import ROOT_PATH
from db_adapter import Db
import main

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/server_log_parser' \
                                                 '/sample_with_mixed_lines.log'


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


def test_calculating_hash(mock_testcase_row):
    text = f'{mock_testcase_row["caller"]},{mock_testcase_row["method"]},{mock_testcase_row["parameters"]}'
    assert common.calculate_hash(text) == '3cb9508b3fdc131a32dd8085fd62e3718ffe03f09e031961c94f36d9b210ef84'


def test_retrieving_cols_and_params_from_dict(mock_testcase_row):
    expected_cols = 'caller, method, parameters, hash'
    expected_params = ':caller, :method, :parameters, :hash'
    actual = common.retrieve_cols_and_params(mock_testcase_row)

    assert actual == (expected_cols, expected_params)


def test_distinguishing_objects_having_same_hash(mock_mapped_list, mock_mapped_list_distinguished):
    common.distinguish_objects_having_same_hash(mock_mapped_list)
    assert mock_mapped_list == mock_mapped_list_distinguished


@pytest.mark.asyncio
async def test_db_connection(db: Db):
    db_name = await db.query_one('SELECT current_database();')
    assert db_name == 'tests'


@pytest.mark.asyncio
async def test_creating_tables(db: Db):
    sql = "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1;"
    result_rows = await db.query_all(sql)
    result = [r[0] for r in result_rows]

    assert result == ['benchmark_description', 'benchmark_values', 'testcase']

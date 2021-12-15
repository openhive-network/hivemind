from __future__ import annotations

import pytest

import parser


@pytest.fixture
def sample_row() -> dict[str, str]:
    return {'api': 'bridge',
            'method': 'get_account_posts',
            'parameters': '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
            'hash': '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75',
            }


def test_calculating_hash(sample_row):
    text = f'{sample_row["api"]},{sample_row["method"]},{sample_row["parameters"]}'
    assert parser.calculate_hash(text) == '3cb9508b3fdc131a32dd8085fd62e3718ffe03f09e031961c94f36d9b210ef84'


def test_retrieving_cols_and_params_from_dict(sample_row):
    expected_cols = 'api, method, parameters, hash'
    expected_params = ':api, :method, :parameters, :hash'
    actual = parser.retrieve_cols_and_params(sample_row)

    assert actual == (expected_cols, expected_params)

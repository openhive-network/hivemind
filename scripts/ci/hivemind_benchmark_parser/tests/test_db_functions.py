import parser

COLS_ARGS = {'api': 'bridge',
             'method': 'get_account_posts',
             'parameters': '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
             'hash': '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75'
             }


def test_calculating_hash():
    text = f'{COLS_ARGS["api"]},{COLS_ARGS["method"]},{COLS_ARGS["parameters"]}'
    assert parser.calculate_hash(text) == '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75'


def test_retrieving_cols_and_params_from_dict():
    expected_cols = 'api, method, parameters, hash'
    expected_params = ':api, :method, :parameters, :hash'
    actual = parser.retrieve_cols_and_params(COLS_ARGS)

    assert actual == (expected_cols, expected_params)

import parser

values = dict(api='bridge',
              method='get_account_posts',
              parameters='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
              hash=''
              )


def test_calculating_hash():
    text = ','.join(values.values())
    assert parser.calculate_hash(text) == '250d93d73b8ec26adf6da27daa792d632d38ed3f3169f6d3019743e89214e030'


def test_retrieving_cols_and_params_from_dict():
    expected_cols = 'api, method, parameters, hash'
    expected_params = ':api, :method, :parameters, :hash'
    actual = parser.retrieve_cols_and_params(values)

    assert actual == (expected_cols, expected_params)

import parser


def test_single_log_line_parsing_format1():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "bridge.get_ranked_posts", ' \
           '"params": {"sort": "payout", "tag": "all", "observer": "joeyarnoldvn", "limit": 5}} processed in 0.0058s'
    parse_result = parser.parse_log_line(line)

    assert parse_result.api == 'bridge'
    assert parse_result.method == 'get_ranked_posts'
    assert parse_result.parameters == '{"sort": "payout", "tag": "all", "observer": "joeyarnoldvn", "limit": 5}'
    assert parse_result.total_time == 0.0058
    assert parse_result.id is None


def test_single_log_line_parsing_format2():
    line = 'Request: {"jsonrpc": "2.0", "id": "b8d63786-b314-4a36-b5ed-331f75210447", ' \
           '"method": "bridge.get_payout_stats", "params": [10]} processed in 0.0072s'
    parse_result = parser.parse_log_line(line)

    assert parse_result.api == 'bridge'
    assert parse_result.method == 'get_payout_stats'
    assert parse_result.parameters == '[10]'
    assert parse_result.total_time == 0.0072
    assert parse_result.id is None


def test_single_log_line_parsing_format3():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "call", ' \
           '"params": {"api": "condenser_api", "method": "get_account_votes", "params": ["gtg"]}} processed in 0.0012s'
    parse_result = parser.parse_log_line(line)

    assert parse_result.api == 'condenser_api'
    assert parse_result.method == 'call'
    assert parse_result.parameters == '{"api": "condenser_api", "method": "get_account_votes", "params": ["gtg"]}'
    assert parse_result.total_time == 0.0012
    assert parse_result.id is None


def test_single_log_line_parsing_format4():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "call", ' \
           '"params": ["bridge_api", "account_notifications", ["steemit", 15, 20]]} processed in 0.0015s'
    parse_result = parser.parse_log_line(line)

    assert parse_result.api == 'bridge_api'
    assert parse_result.method == 'call'
    assert parse_result.parameters == '["bridge_api", "account_notifications", ["steemit", 15, 20]]'
    assert parse_result.total_time == 0.0015
    assert parse_result.id is None


def test_empty_log_line_parsing():
    assert parser.parse_log_line('') is None


def test_wrong_line_parsing():
    line = 'INFO - Request-Process-Time-Logger - ' \
           'Request: {"jsonrpc": "2.0", "id": 1, "method": "bridge.get_ranked_posts", ' \
           '"params": {"sort": "created", "tag": "hive-135485", "start_author": "", ' \
           '"start_permlink": "pinpost11", "limit": 1}} processed in 0.0020s'
    assert parser.parse_log_line(line) is None

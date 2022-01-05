import server_log_parser as parser


def test_server_log_single_line_parsing_format1():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "bridge.get_ranked_posts", ' \
           '"params": {"sort": "payout", "tag": "all", "observer": "joeyarnoldvn", "limit": 5}} processed in 0.0058s'
    parsed = parser.parse_log_line(line)

    assert parsed['caller'] == 'bridge'
    assert parsed['method'] == 'get_ranked_posts'
    assert parsed['params'] == '{"sort": "payout", "tag": "all", "observer": "joeyarnoldvn", "limit": 5}'
    assert parsed['value'] == 6
    assert parsed['unit'] == 'ms'


def test_server_log_single_line_parsing_format2():
    line = 'Request: {"jsonrpc": "2.0", "id": "b8d63786-b314-4a36-b5ed-331f75210447", ' \
           '"method": "bridge.get_payout_stats", "params": [10]} processed in 0.0072s'
    mapped = parser.parse_log_line(line)

    assert mapped['caller'] == 'bridge'
    assert mapped['method'] == 'get_payout_stats'
    assert mapped['params'] == '[10]'
    assert mapped['value'] == 7
    assert mapped['unit'] == 'ms'


def test_server_log_single_line_parsing_format3():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "call", ' \
           '"params": {"api": "condenser_api", "method": "get_account_votes", "params": ["gtg"]}} processed in 0.0012s'
    mapped = parser.parse_log_line(line)

    assert mapped['caller'] == 'condenser_api'
    assert mapped['method'] == 'get_account_votes'
    assert mapped['params'] == '["gtg"]'
    assert mapped['value'] == 1
    assert mapped['unit'] == 'ms'


def test_server_log_single_line_parsing_format4():
    line = 'Request: {"jsonrpc": "2.0", "id": 1, "method": "call", ' \
           '"params": ["bridge_api", "account_notifications", ["steemit", 15, 20]]} processed in 0.0015s'
    mapped = parser.parse_log_line(line)

    assert mapped['caller'] == 'bridge_api'
    assert mapped['method'] == 'account_notifications'
    assert mapped['params'] == '["steemit", 15, 20]'
    assert mapped['value'] == 2
    assert mapped['unit'] == 'ms'


def test_empty_server_log_line_parsing():
    assert parser.parse_log_line('') is None


def test_wrong_server_log_line_parsing():
    line = 'INFO - Request-Process-Time-Logger - ' \
           'Request: {"jsonrpc": "2.0", "id": 1, "method": "bridge.get_ranked_posts", ' \
           '"params": {"sort": "created", "tag": "hive-135485", "start_author": "", ' \
           '"start_permlink": "pinpost11", "limit": 1}} processed in 0.0020s'
    assert parser.parse_log_line(line) is None

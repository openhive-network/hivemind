import datetime
from pathlib import Path
import socket
from typing import Final

import pytest

from constants import ROOT_PATH
from db_adapter import Db
import main
import server_log_parser as parser

SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/server_log_parser' \
                                                 '/sample_with_mixed_lines.log'


@pytest.mark.asyncio
async def test_server_log_mode(db: Db, sql_select_all: str):
    sys_argv = ['-m', '1',
                '-f', str(SAMPLE_LOG_WITH_MIXED_LINES),
                '-db', '',
                '--desc', 'server parser functional test',
                '--exec-env-desc', 'mock db',
                '--server-name', 'localhost',
                '--app-version', '1.0',
                '--testsuite-version', '2.0',
                ]

    args = main.init_argparse(sys_argv)
    timestamp = datetime.datetime.now()

    benchmark_id = await main.insert_benchmark_description(db, args=args, timestamp=timestamp)

    await parser.main(db, file=Path(args.file), benchmark_id=benchmark_id)

    actual = await db.query_all(sql_select_all)

    benchmark = ('server parser functional test', 'mock db', timestamp.replace(microsecond=0), 'localhost',
                 '1.0', '2.0', socket.gethostname())

    testcase1 = ('bridge', 'get_account_posts', '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                 '6e1d6e836a45438f7e8c130f8f85a2cdacf81ab7d0b5fae4875d4ed2f083cd4a')

    testcase2 = ('bridge', 'get_community', '{"name": "hive-135485"}',
                 '60db22f04dfe57632c5ac6b03a154caeb16db50a87d2be9670a525d5c57637f1')

    testcase3 = ('bridge', 'get_account_posts', '{"sort": "blog", "account": "steemit"}',
                 'e67acec4eef88c4e462efea6846004ad0487d20982f537d4e7bd87da3b50d730')

    assert actual == [(*benchmark, *testcase1, 74, 'ms'),
                      (*benchmark, *testcase1, 74, 'ms'),
                      (*benchmark, *testcase1, 74, 'ms'),
                      (*benchmark, *testcase2, 15, 'ms'),
                      (*benchmark, *testcase3, 26, 'ms')]

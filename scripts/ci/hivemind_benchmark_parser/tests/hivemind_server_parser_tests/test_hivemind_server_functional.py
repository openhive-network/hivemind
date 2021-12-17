import datetime
from pathlib import Path
import socket
from typing import Final

import pytest
from sqlalchemy.engine import URL

import common
from constants import ROOT_PATH
from db_adapter import Db
import hivemind_server_parser as parser
import main

DB_SCHEMA: Final = ROOT_PATH / 'db/db-schema.sql'
SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/hivemind_server_parser' \
                                                 '/sample_with_mixed_lines.log'


@pytest.mark.asyncio
@pytest.fixture
async def db(postgresql) -> Db:
    config = {'drivername': 'postgresql',
              'username': postgresql.info.user,
              'host': postgresql.info.host,
              'port': postgresql.info.port,
              'database': postgresql.info.dbname,
              }
    db = await Db.create(URL.create(**config))
    await build_schema(db)
    yield db
    db.close()
    await db.wait_closed()


async def build_schema(db: Db):
    with open(DB_SCHEMA, 'r') as file:
        create_schema_sql = file.read()
    await db.query(create_schema_sql)


def select_for_all():
    return "SELECT b.description, " \
           " b.execution_environment_description," \
           " b.timestamp," \
           " b.server_name," \
           " b.app_version," \
           " b.testsuite_version," \
           " b.runner," \
           " t.caller," \
           " t.method," \
           " t.params," \
           " t.hash," \
           " bv.value," \
           " bv.unit" \
           " FROM" \
           " public.benchmark_values bv" \
           " JOIN public.benchmark_description b ON (bv.benchmark_description_id=b.id)" \
           " JOIN public.testcase t ON (bv.testcase_hash = t.hash)"


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


@pytest.mark.asyncio
async def test_hivemind_server_mode(db: Db):
    sys_argv = ['-m', '1',
                '-f', str(SAMPLE_LOG_WITH_MIXED_LINES),
                '-db', '',
                '--desc', 'Test description',
                '--exec-env-desc', 'Mock database',
                '--server-name', 'localhost',
                '--app-version', '1.00',
                '--testsuite-version', '2.00',
                ]

    args = main.init_argparse(sys_argv)

    benchmark_description = common.benchmark_description(args)
    benchmark_timestamp = datetime.datetime.strptime(benchmark_description['timestamp'], '%Y/%m/%d, %H:%M:%S'),

    benchmark_id = await common.insert_row_with_returning(db,
                                                          table='public.benchmark_description',
                                                          cols_args=benchmark_description,
                                                          additional=' RETURNING id',
                                                          )

    await parser.main(Path(args.file), db, benchmark_id)

    actual = await db.query_all(select_for_all())

    benchmark = (
        'Test description', 'Mock database', *benchmark_timestamp, 'localhost', '1.00', '2.00', socket.gethostname())

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

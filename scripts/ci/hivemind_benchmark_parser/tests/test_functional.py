import datetime
import socket
from typing import Final

import pytest
from sqlalchemy.engine import URL

from constants import ROOT_PATH
from db_adapter import Db
import parser

DB_SCHEMA: Final = ROOT_PATH / 'db/db-schema.sql'
SAMPLE_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'input/sample_with_mixed_lines.txt'


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
    return db


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
           " r.api," \
           " r.method," \
           " r.parameters," \
           " r.hash," \
           " rt.execution_time" \
           " FROM" \
           " public.request_times rt" \
           " JOIN public.benchmark_description b ON (rt.benchmark_id=b.id)" \
           " JOIN public.request r ON (rt.request_id = r.id)"


@pytest.mark.asyncio
async def test_db_connection(db: Db):
    db_name = await db.query_one('SELECT current_database();')
    assert db_name == 'tests'


@pytest.mark.asyncio
async def test_creating_tables(db: Db):
    table_names_sql = "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1;"
    result_rows = await db.query_all(table_names_sql)
    result = [r[0] for r in result_rows]

    assert result == ['benchmark_description', 'request', 'request_times']


@pytest.mark.asyncio
async def test_parser(db: Db):
    sys_argv = ['-f', str(SAMPLE_LOG_WITH_MIXED_LINES),
                '-db', '',
                '--desc', 'Test description',
                '--exec-env-desc', 'Mock database',
                '--server-name', 'localhost',
                '--app-version', '1.00',
                '--testsuite-version', '2.00',
                ]

    args = parser.init_argparse(sys_argv)
    benchmark_description = parser.benchmark_description(args)

    log_lines = parser.get_lines_from_log_file(args.file)
    parsed_list = parser.prepare_db_records_from_log_lines(log_lines)

    benchmark_id = await parser.insert_row_with_returning(db,
                                                          table='public.benchmark_description',
                                                          cols_args=benchmark_description,
                                                          additional=' RETURNING id',
                                                          )

    request_ids = await parser.insert_requests(db, parsed_list)

    for idx, request_id in enumerate(request_ids):
        await parser.insert_row(db,
                                'public.request_times',
                                {'benchmark_id': benchmark_id,
                                 'request_id': request_id,
                                 'testcase_id': parsed_list[idx].id,
                                 'execution_time': round(parsed_list[idx].total_time * 10 ** 3),
                                 })

    actual = await db.query_all(select_for_all())
    db.close()
    await db.wait_closed()

    benchmark = ('Test description', 'Mock database',
                 datetime.datetime.strptime(benchmark_description['timestamp'], '%Y/%m/%d, %H:%M:%S'),
                 'localhost', '1.00', '2.00', socket.gethostname())

    request1 = ('bridge', 'get_account_posts', '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                '6e1d6e836a45438f7e8c130f8f85a2cdacf81ab7d0b5fae4875d4ed2f083cd4a')

    request2 = ('bridge', 'get_community', '{"name": "hive-135485"}',
                '60db22f04dfe57632c5ac6b03a154caeb16db50a87d2be9670a525d5c57637f1')

    request3 = ('bridge', 'get_account_posts', '{"sort": "blog", "account": "steemit"}',
                'e67acec4eef88c4e462efea6846004ad0487d20982f537d4e7bd87da3b50d730')

    assert actual == [(*benchmark, *request1, 74),
                      (*benchmark, *request1, 74),
                      (*benchmark, *request1, 74),
                      (*benchmark, *request2, 15),
                      (*benchmark, *request3, 26)]

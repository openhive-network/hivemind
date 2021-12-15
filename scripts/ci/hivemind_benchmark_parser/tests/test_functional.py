import datetime
import socket

import pytest
from sqlalchemy.engine import URL

from constants import ROOT_PATH
from db_adapter import Db
import parser

DB_SCHEMA = ROOT_PATH / 'db/db-schema.sql'
SAMPLE_LOG_WITH_MIXED_LINES = ROOT_PATH / 'input/sample_with_mixed_lines.txt'


@pytest.mark.asyncio
@pytest.fixture
async def db(postgresql):
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


@pytest.mark.asyncio
async def test_db_connection(db: Db):
    db_name = await db.query_one('SELECT current_database();')
    assert db_name == 'tests'


@pytest.mark.asyncio
async def test_creating_tables(db: Db):
    table_names_sql = "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1;"
    result_rows = await db.query_all(table_names_sql)
    result = [r[0] for r in result_rows]

    assert result == ['benchmark_description', 'benchmark_times', 'testcase']


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
    benchmark = parser.create_benchmark(args)

    log_lines = parser.get_lines_from_log_file(args.file)
    parsed_list = parser.prepare_db_records_from_log_lines(log_lines)

    benchmark_id = await parser.insert_row_with_returning(db,
                                                          table='public.benchmark_description',
                                                          cols_args=vars(benchmark),
                                                          additional=' RETURNING id',
                                                          )

    testcase_ids = await parser.insert_testcases(db, parsed_list)

    for idx, testcase_id in enumerate(testcase_ids):
        await parser.insert_row(db,
                                'public.benchmark_times',
                                {'benchmark_id': benchmark_id,
                                 'testcase_id': testcase_id,
                                 'request_id': parsed_list[idx].id,
                                 'execution_time': round(parsed_list[idx].total_time * 10 ** 3),
                                 })

    benchmark_description = await db.query_all("SELECT * FROM public.benchmark_description;")
    benchmark_times = await db.query_all("SELECT * FROM public.benchmark_times;")
    testcases = await db.query_all("SELECT * FROM public.testcase")

    db.close()
    await db.wait_closed()

    assert benchmark_description == [(1, 'Test description', 'Mock database',
                                      datetime.datetime.strptime(benchmark.timestamp, '%Y/%m/%d, %H:%M:%S'),
                                      'localhost', '1.00', '2.00', socket.gethostname())]

    assert benchmark_times == [(1, 1, 1, 74), (1, 1, 2, 74), (1, 1, 3, 74), (1, 2, 1, 15), (1, 3, 1, 26)]

    assert testcases == [(1, 'bridge', 'get_account_posts', '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                          '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75'),
                         (2, 'bridge', 'get_community', '{"name": "hive-135485"}',
                          'f296513750952a8640e5e0d675e49ea7d941b5fb0f5b1cc8d4fb87c5b4140515'),
                         (3, 'bridge', 'get_account_posts', '{"sort": "blog", "account": "steemit"}',
                          '451d12b59f3252afe6177250bd8e6be703f81e48f83da59f68a05a029abba089')]

from __future__ import annotations

from typing import Final

import pytest
from sqlalchemy.engine import URL

import common
from common import MappedDbData
from constants import ROOT_PATH
from db_adapter import Db
import sync_log_parser

DB_SCHEMA: Final = ROOT_PATH / 'db/db-schema.sql'
SAMPLE_SYNC_LOG_WITH_MIXED_LINES: Final = ROOT_PATH / 'tests/mock_data/sync_log_parser' \
                                                      '/sample_with_mixed_lines.log'


async def build_schema(db: Db):
    with open(DB_SCHEMA, 'r') as file:
        create_schema_sql = file.read()
    await db.query(create_schema_sql)


def mock_mapped(caller: str, method: str, params: str, value: int, unit: str, id: int = None, hash: str = None) \
        -> MappedDbData:
    mapped = MappedDbData(caller, method, params, value, unit)
    mapped.id = id
    mapped.hash = hash
    return mapped


def first_testcase(id: int) -> MappedDbData:
    return mock_mapped(caller='bridge',
                       method='get_account_posts',
                       params='{"sort": "replies", "account": "gtg", "observer": "gtg"}',
                       value=74,
                       unit='ms',
                       id=id,
                       hash='6e1d6e836a45438f7e8c130f8f85a2cdacf81ab7d0b5fae4875d4ed2f083cd4a',
                       )


def second_testcase(id: int) -> MappedDbData:
    return mock_mapped(caller='bridge',
                       method='get_community',
                       params='{"name": "hive-135485"}',
                       value=15,
                       unit='ms',
                       id=id,
                       hash='60db22f04dfe57632c5ac6b03a154caeb16db50a87d2be9670a525d5c57637f1',
                       )


def third_testcase(id: int) -> MappedDbData:
    return mock_mapped(caller='bridge',
                       method='get_account_posts',
                       params='{"sort": "blog", "account": "steemit"}',
                       value=26,
                       unit='ms',
                       id=id,
                       hash='e67acec4eef88c4e462efea6846004ad0487d20982f537d4e7bd87da3b50d730',
                       )


@pytest.fixture
def mock_mapped_list() -> list[MappedDbData]:
    return [first_testcase(id=1),
            first_testcase(id=1),
            first_testcase(id=1),
            second_testcase(id=1),
            third_testcase(id=1),
            ]


@pytest.fixture
def mock_mapped_list_distinguished() -> list[MappedDbData]:
    return [first_testcase(id=1),
            first_testcase(id=2),
            first_testcase(id=3),
            second_testcase(id=1),
            third_testcase(id=1),
            ]


@pytest.fixture
def mock_testcase_row() -> dict[str, str]:
    return {'caller': 'bridge',
            'method': 'get_account_posts',
            'parameters': '{"sort": "replies", "account": "gtg", "observer": "gtg"}',
            'hash': '3fb95b06c2116b63740dfabf971380a26d0612934eeebf990ba033fd3aa28e75',
            }


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


@pytest.fixture
def sql_select_all() -> str:
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


@pytest.fixture
def interesting_sync_log_strings():
    text = common.get_text_from_log_file(SAMPLE_SYNC_LOG_WITH_MIXED_LINES)
    return sync_log_parser.extract_interesting_log_strings(text)

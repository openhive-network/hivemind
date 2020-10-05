import pytest

@pytest.fixture(scope="module")
def database_connection():
    from hive.db.adapter import Db
    yield Db.instance()

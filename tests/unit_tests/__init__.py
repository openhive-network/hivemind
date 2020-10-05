"""Hive server and API tests."""
from hive.conf import Conf
from hive.db.adapter import Db

db = Db("postgresql://hive@localhost:5432")
db.query_no_return("DROP DATABASE IF EXISTS hive_test")
db.query_no_return("CREATE DATABASE hive_test")

db = Db("postgresql://hive@localhost:5432/hive_test")

Db.set_shared_instance(db)
from hive.db.db_state import DbState
DbState.initialize()

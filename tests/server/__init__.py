"""Hive server and API tests."""
from hivemind.conf import Conf
from hivemind.db.adapter import Db

Db.set_shared_instance(Conf.init_test().db())

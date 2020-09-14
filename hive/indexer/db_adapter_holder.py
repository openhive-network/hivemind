from hive.db.adapter import Db

import logging
log = logging.getLogger(__name__)

class DbAdapterHolder(object):
    db : Db = None

    _inside_tx = False
    _use_tx = True

    @classmethod
    def setup_shared_db_access(cls, sharedDb):
        cls.db = sharedDb
        cls._use_tx = False

    @classmethod
    def setup_own_db_access(cls, sharedDb):
        cls.db = sharedDb.clone()
        cls._use_tx = True

    @classmethod
    def tx_active(cls):
        return cls._inside_tx

    @classmethod
    def beginTx(cls):
        if cls._use_tx:
            cls.db.query("START TRANSACTION")
            cls._inside_tx = True

    @classmethod
    def commitTx(cls):
        if cls._use_tx:
            cls.db.query("COMMIT")
            cls._inside_tx = False

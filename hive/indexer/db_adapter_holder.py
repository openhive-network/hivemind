import logging
log = logging.getLogger(__name__)

class DbAdapterHolder(object):
    db = None

    _inside_tx = False

    @classmethod
    def setup_own_db_access(cls, sharedDb, name):
        cls.db = sharedDb.clone(name)

    @classmethod
    def close_own_db_access(cls):
        if cls.db is not None:
          cls.db.close()

    @classmethod
    def tx_active(cls):
        return cls._inside_tx

    @classmethod
    def beginTx(cls):
        cls.db.query("START TRANSACTION")
        cls._inside_tx = True

    @classmethod
    def commitTx(cls):
        cls.db.query("COMMIT")
        cls._inside_tx = False

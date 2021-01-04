import logging
log = logging.getLogger(__name__)

class DbAdapterHolder(object):
    db = None

    _inside_tx = False

    @classmethod
    def setup_own_db_access(cls, sharedDb):
        cls.db = sharedDb.clone()

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

import logging
log = logging.getLogger(__name__)

class DbLiveHolder(object):
    _live_db = None

    @classmethod
    def close_own_db_access(cls):
        if cls._live_db is not None:
          cls._live_db.close()

class DbAdapterHolder(object):
    db = None

    _inside_sync_tx = False
    _live_context = False

    @classmethod
    def setup_own_db_access(cls, sharedDb, name, live_context):
        cls._live_context = live_context

        if cls._live_context:
          if DbLiveHolder._live_db is None:
            DbLiveHolder._live_db = sharedDb.clone(name)
          cls.db = DbLiveHolder._live_db
        else:
          cls.db = sharedDb.clone(name)

    @classmethod
    def close_own_db_access(cls):
        if cls.db is not None:
          cls.db.close()

    @classmethod
    def sync_tx_active(cls):
        return cls._inside_sync_tx

    @classmethod
    def beginTx(cls):
        if not cls._live_context:
          cls.db.query("START TRANSACTION")
          cls._inside_sync_tx = True

    @classmethod
    def commitTx(cls):
        if not cls._live_context:
          cls.db.query("COMMIT")
          cls._inside_sync_tx = False

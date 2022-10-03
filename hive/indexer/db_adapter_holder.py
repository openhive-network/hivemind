import logging

log = logging.getLogger(__name__)


class DbLiveContextHolder(object):
    _live_context = False

    @classmethod
    def set_live_context(cls, live_context):
        cls._live_context = live_context

    @classmethod
    def is_live_context(cls):
        return cls._live_context


class DbAdapterHolder(object):
    db = None

    _inside_sync_tx = False

    @classmethod
    def setup_own_db_access(cls, sharedDb, name):
        if DbLiveContextHolder.is_live_context():
            cls.db = sharedDb
        else:
            cls.db = sharedDb.clone(name)

    @classmethod
    def close_own_db_access(cls):
        if cls.db is not None:
            cls.db.close()
            cls.db = None

    @classmethod
    def sync_tx_active(cls):
        return cls._inside_sync_tx

    @classmethod
    def beginTx(cls):
        if not DbLiveContextHolder.is_live_context():
            cls.db.query("START TRANSACTION")
            cls._inside_sync_tx = True

    @classmethod
    def commitTx(cls):
        if not DbLiveContextHolder.is_live_context():
            cls.db.query("COMMIT")
            cls._inside_sync_tx = False

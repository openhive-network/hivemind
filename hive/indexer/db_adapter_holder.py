import logging
log = logging.getLogger(__name__)

class DbAdapterHolder(object):
    db = None

    _inside_tx = False

    @classmethod
    def setup_db_access(self, sharedDb):
        self.db = sharedDb.clone()

    @classmethod
    def tx_active(self):
        return self._inside_tx

    @classmethod
    def beginTx(self):
        self.db.query("START TRANSACTION")
        self._inside_tx = True

    @classmethod
    def commitTx(self):
        self.db.query("COMMIT")
        self._inside_tx = False

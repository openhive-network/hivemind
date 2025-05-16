"""Follow count management for accounts."""

import logging
from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.misc import chunks

log = logging.getLogger(__name__)


class FollowCount(DbAdapterHolder):
    """Manages follow count recalculation for accounts."""

    accounts = set()

    @classmethod
    def add_accounts(cls, accounts):
        """Add an account to the follow recalculation queue."""
        cls.accounts.update(accounts)

    @classmethod
    def flush(cls):
        """Flush follow count updates to database."""
        if not cls.accounts:
            return 0

        cls.beginTx()
        for chunk in chunks(cls.accounts, 1000):
            cls.db.query_prepared(f"SELECT {SCHEMA_NAME}.update_follow_count(ARRAY[{','.join(chunk)}])")
        cls.commitTx()

        count = len(cls.accounts)
        cls.accounts.clear()
        return count

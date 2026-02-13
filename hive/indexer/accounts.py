"""Accounts indexer — registration and updates now handled by SQL.

Retains in-memory id map (load_ids/get_id) used by PostDataCache and live sync.
"""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


class Accounts(DbAdapterHolder):
    """Manages account id map and `hive_accounts` table."""

    # name->id map
    _ids = {}

    # in-mem id->rank map
    _ranks = {}

    @classmethod
    def load_ids(cls):
        """Load a full (name: id) dict into memory."""
        assert not cls._ids, "id map already loaded"
        cls._ids = dict(
            DbAdapterHolder.common_block_processing_db().query_all(f"SELECT name, id FROM {SCHEMA_NAME}.hive_accounts")
        )

    @classmethod
    def clear_ids(cls):
        """Wipe id map. Only used for db migration #5."""
        cls._ids = None

    @classmethod
    def get_id(cls, name):
        """Get account id by name. Throw if not found."""
        assert isinstance(name, str), "account name should be string"
        assert name in cls._ids, f'Account \'{name}\' does not exist'
        return cls._ids[name]

    @classmethod
    def get_id_noexept(cls, name):
        """Get account id by name. Return None if not found."""
        assert isinstance(name, str), "account name should be string"
        return cls._ids.get(name, None)

    @classmethod
    def exists(cls, names):
        """Check if an account name exists."""
        if isinstance(names, str):
            return names in cls._ids
        return False

    @classmethod
    def check_names(cls, names):
        """Check which names from name list does not exists in the database"""
        assert isinstance(names, list), "Expecting list as argument"
        return [name for name in names if name not in cls._ids]

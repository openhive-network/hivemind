"""Accounts indexer."""

import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.account import get_profile_str
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)

class Accounts(DbAdapterHolder):
    """Manages account id map, dirty queue, and `hive_accounts` table."""

    _updates_data = {}

    inside_flush = False

    # name->id map
    # name->id mapdb
    _ids = {}

    # in-mem id->rank map
    _ranks = {}

    # account core methods
    # --------------------

    @classmethod
    def update_op(cls, update_operation, allow_change_posting):
        """Save json_metadata."""

        if cls.inside_flush:
            log.exception("Adding new update-account-info into '_updates_data' dict")
            raise RuntimeError("Fatal error")

        key = update_operation['account']
        (_posting_json_metadata, _json_metadata) = get_profile_str(update_operation)

        if key in cls._updates_data:
            if allow_change_posting:
                cls._updates_data[key]['allow_change_posting'] = True
                cls._updates_data[key]['posting_json_metadata'] = _posting_json_metadata

            cls._updates_data[key]['json_metadata'] = _json_metadata
        else:
            cls._updates_data[key] = {
                'allow_change_posting': allow_change_posting,
                'posting_json_metadata': _posting_json_metadata,
                'json_metadata': _json_metadata,
            }

    @classmethod
    def load_ids(cls):
        """Load a full (name: id) dict into memory."""
        assert not cls._ids, "id map already loaded"
        cls._ids = dict(Db.data_sync_instance().query_all(f"SELECT name, id FROM {SCHEMA_NAME}.hive_accounts"))

    @classmethod
    def clear_ids(cls):
        """Wipe id map. Only used for db migration #5."""
        cls._ids = None

    @classmethod
    def default_score(cls, name):
        """Return default notification score based on rank."""
        _id = cls.get_id(name)
        rank = cls._ranks[_id] if _id in cls._ranks else 1000000
        if rank < 200:
            return 70  # 0.02% 100k
        if rank < 1000:
            return 60  # 0.1%  10k
        if rank < 6500:
            return 50  # 0.5%  1k
        if rank < 25000:
            return 40  # 2.0%  100
        if rank < 100000:
            return 30  # 8.0%  15
        return 20

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

    @classmethod
    def get_json_data(cls, source):
        """json-data preprocessing."""
        return escape_characters(source)

    @classmethod
    def register(cls, name, op_details, block_date, block_num):
        """Block processing: register "candidate" names.

        There are four ops which can result in account creation:
        *account_create*, *account_create_with_delegation*, *pow*,
        and *pow2*. *pow* ops result in account creation only when
        the account they name does not already exist!
        """

        if name is None:
            return False

        # filter out names which already registered
        if cls.exists(name):
            return True

        (_posting_json_metadata, _json_metadata) = get_profile_str(op_details)

        sql = f"""
                  INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at, posting_json_metadata, json_metadata )
                  VALUES ( '{name}', '{block_date}', {cls.get_json_data(_posting_json_metadata)}, {cls.get_json_data(_json_metadata)} )
                  RETURNING id
              """

        new_id = Db.data_sync_instance().query_one(sql)
        if new_id is None:
            return False
        cls._ids[name] = new_id

        # post-insert: pass to communities to check for new registrations
        from hive.indexer.community import Community

        if block_num > Community.start_block:
            Community.register(name, block_date, block_num)

        return True

    @classmethod
    def flush(cls):
        """Flush json_metadatafrom cache to database"""

        cls.inside_flush = True
        n = 0

        if cls._updates_data:
            cls.beginTx()

            sql = f"""
                    UPDATE {SCHEMA_NAME}.hive_accounts ha
                    SET
                    posting_json_metadata = 
                            (
                                CASE T2.allow_change_posting
                                    WHEN True THEN T2.posting_json_metadata
                                    ELSE ha.posting_json_metadata
                                END
                            ),
                    json_metadata = T2.json_metadata
                    FROM
                    (
                      SELECT
                        allow_change_posting,
                        posting_json_metadata,
                        json_metadata,
                        name
                      FROM
                      (
                      VALUES
                        -- allow_change_posting, posting_json_metadata, json_metadata, name
                        {{}}
                      )T( allow_change_posting, posting_json_metadata, json_metadata, name )
                    )T2
                    WHERE ha.name = T2.name
                """

            values = []
            values_limit = 1000

            for name, data in cls._updates_data.items():
                values.append(
                    f"({data['allow_change_posting']}, {cls.get_json_data(data['posting_json_metadata'])}, {cls.get_json_data(data['json_metadata'])}, '{name}')"
                )

                if len(values) >= values_limit:
                    values_str = ','.join(values)
                    actual_query = sql.format(values_str)
                    cls.db.query_prepared(actual_query)
                    values.clear()

            if len(values) > 0:
                values_str = ','.join(values)
                actual_query = sql.format(values_str)
                cls.db.query_prepared(actual_query)
                values.clear()

            n = len(cls._updates_data)
            cls._updates_data.clear()
            cls.commitTx()

        cls.inside_flush = False

        return n

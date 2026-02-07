import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


def _sanitize_nul(val):
    """Replace NUL chars with spaces — PostgreSQL text columns cannot store \\x00."""
    if val is None:
        return None
    return val.replace('\x00', ' ') if '\x00' in val else val


class PostDataCache(DbAdapterHolder):
    """Provides cache for DB operations on post data table in order to speed up massive sync"""

    _data = {}

    @classmethod
    def is_cached(cls, pid):
        """Check if data is cached"""
        return pid in cls._data

    @classmethod
    def add_data(cls, pid, post_data, is_new_post):
        """Add data to cache"""
        if not cls.is_cached(pid):
            cls._data[pid] = post_data
            cls._data[pid]['is_new_post'] = is_new_post
        else:
            assert not is_new_post
            for k, data in post_data.items():
                if data is not None:
                    cls._data[pid][k] = data

    @classmethod
    def get_post_body(cls, pid):
        """Returns body of given post from collected cache or from underlying DB storage."""
        try:
            post_data = cls._data[pid]
        except KeyError:
            sql = f"""
                  SELECT hpd.body FROM {SCHEMA_NAME}.hive_post_data hpd WHERE hpd.id = :post_id;
                  """
            row = cls.db.query_row(sql, post_id=pid)
            post_data = dict(row._mapping)
        return post_data['body']

    @classmethod
    def flush(cls, print_query=False):
        """Flush data from cache to db"""
        if not cls._data:
            return 0

        insert_items = []
        update_items = []
        for k, data in cls._data.items():
            item = (
                k,
                data['is_root'],
                _sanitize_nul(data['title']),
                _sanitize_nul(data['body']),
                _sanitize_nul(data['json']),
            )
            if data['is_new_post']:
                insert_items.append(item)
            else:
                update_items.append(item)

        cls.beginTx()

        insert_ph = (
            ','.join(['(%s, %s, %s, %s, %s)'] * len(insert_items))
            if insert_items
            else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'
        )
        update_ph = (
            ','.join(['(%s, %s, %s, %s, %s)'] * len(update_items))
            if update_items
            else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'
        )

        sql = f"""
            WITH insert_values(id, is_root, title, body, json) AS (
                SELECT * FROM (VALUES {insert_ph}) AS v(id, is_root, title, body, json)
                WHERE v.id IS NOT NULL
            ),
            update_values(id, is_root, title, body, json) AS (
                SELECT * FROM (VALUES {update_ph}) AS v(id, is_root, title, body, json)
            ),
            insert_post_data AS (
                INSERT INTO {SCHEMA_NAME}.hive_post_data
                SELECT id, title, body, json FROM insert_values
                RETURNING id
            ),
            update_post_data AS (
                UPDATE {SCHEMA_NAME}.hive_post_data AS hpd
                SET title = COALESCE( i.title, hpd.title ),
                    body = COALESCE( i.body, hpd.body ),
                    json = COALESCE( i.json, hpd.json )
                FROM update_values i
                WHERE hpd.id = i.id AND i.id IS NOT NULL
                RETURNING hpd.id
            ),
            combined AS (
                SELECT id FROM insert_post_data
                UNION ALL
                SELECT id FROM update_post_data
            )
            SELECT {SCHEMA_NAME}.process_hive_post_mentions(array_agg(id))
            FROM combined
        """

        params = []
        for item in insert_items:
            params.extend(item)
        for item in update_items:
            params.extend(item)

        if print_query:
            log.info(f"Executing query:\n{sql}")

        if params:
            cls.db.query_all_raw(sql, tuple(params))
        else:
            cls.db.query_all_raw(sql)

        cls.commitTx()

        n = len(cls._data)
        cls._data.clear()
        return n

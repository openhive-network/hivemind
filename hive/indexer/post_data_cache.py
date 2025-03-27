import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)


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
            post_data = dict(row)
        return post_data['body']

    @classmethod
    def flush(cls, print_query=False):
        """Flush data from cache to db"""
        if cls._data:
            values_insert = []
            values_update = []
            for k, data in cls._data.items():
                title = 'NULL' if data['title'] is None else f"{escape_characters(data['title'])}"
                body = 'NULL' if data['body'] is None else f"{escape_characters(data['body'])}"
                json = 'NULL' if data['json'] is None else f"{escape_characters(data['json'])}"
                value = f"({k},{title},{body},{json})"
                if data['is_new_post']:
                    values_insert.append(value)
                else:
                    values_update.append(value)

            cls.beginTx()
            if len(values_insert) > 0:
                sql = f"""
                    WITH inserted AS (
                        INSERT INTO {SCHEMA_NAME}.hive_post_data (id, title, body, json)
                        VALUES {','.join(values_insert)}
                        RETURNING id
                    )
                    SELECT {SCHEMA_NAME}.process_hive_post_mentions(id) FROM inserted
                """
                if print_query:
                    log.info(f"Executing query:\n{sql}")
                cls.db.query_prepared(sql)
                values_insert.clear()

            if len(values_update) > 0:
                sql = f"""
                    WITH updated AS (
                        UPDATE {SCHEMA_NAME}.hive_post_data AS hpd SET
                            title = COALESCE( data_source.title, hpd.title ),
                            body = COALESCE( data_source.body, hpd.body ),
                            json = COALESCE( data_source.json, hpd.json )
                        FROM (
                            SELECT *
                            FROM (VALUES {','.join(values_update)})
                            AS T(id, title, body, json)
                        ) AS data_source
                        WHERE hpd.id = data_source.id
                        RETURNING hpd.id
                    )
                    SELECT {SCHEMA_NAME}.process_hive_post_mentions(id) FROM updated
                """
                if print_query:
                    log.info(f"Executing query:\n{sql}")
                cls.db.query_prepared(sql)
                values_update.clear()

            cls.commitTx()

        n = len(cls._data.keys())
        cls._data.clear()
        return n

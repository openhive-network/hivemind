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
        if not cls._data:
            return 0

        values_insert = []
        values_update = []
        for k, data in cls._data.items():
            title = 'NULL' if data['title'] is None else f"{escape_characters(data['title'])}"
            body = 'NULL' if data['body'] is None else f"{escape_characters(data['body'])}"
            json = 'NULL' if data['json'] is None else f"{escape_characters(data['json'])}"
            is_root= data['is_root']
            value = f"({k},{is_root},{title},{body},{json})"
            if data['is_new_post']:
                values_insert.append(value)
            else:
                values_update.append(value)

        cls.beginTx()
        cls.db.query_no_return("LOAD 'auto_explain'")
        cls.db.query_no_return("SET auto_explain.log_nested_statements=on")
        cls.db.query_no_return("SET auto_explain.log_min_duration=0")
        cls.db.query_no_return("SET auto_explain.log_analyze=on")
        cls.db.query_no_return("SET auto_explain.log_buffers=on")
        cls.db.query_no_return("SET auto_explain.log_verbose=on")
        sql = f"""
                    WITH insert_values(id, is_root, title, body, json) AS (
                        SELECT * FROM
                        (VALUES {','.join(values_insert) if values_insert else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'}) AS v(id, is_root, title, body, json)
                        WHERE v.id IS NOT NULL
                    ),
                    update_values(id, is_root, title, body, json) AS (
                            SELECT *
                            FROM (VALUES {','.join(values_update) if values_update else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'})
                            AS v(id, is_root, title, body, json)
                    ),
                    insert_post_data AS (
                        INSERT INTO {SCHEMA_NAME}.hive_post_data 
                        SELECT id, title, body, json FROM insert_values
                        RETURNING id
                    ),
                    insert_search_text AS (
                        INSERT INTO {SCHEMA_NAME}.hive_text_search_data (id, body_tsv)
                        SELECT iv.id, to_tsvector('simple', COALESCE(iv.title, '') || ' ' || COALESCE(iv.body, ''))
                        FROM insert_values iv
                        WHERE iv.is_root = true
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
                    update_search_text AS (
                        UPDATE {SCHEMA_NAME}.hive_text_search_data 
                        SET body_tsv = to_tsvector('simple', COALESCE(i.title, '') || ' ' || COALESCE(i.body, '')) --TODO(mickiewicz@syncad.com) title or body could be null
                        FROM update_values i
                        WHERE hive_text_search_data.id = i.id AND i.id IS NOT NULL
                        RETURNING hive_text_search_data.id
                    ),
                    combined AS (
                        SELECT id FROM insert_post_data
                        UNION ALL
                        SELECT id FROM update_post_data
                    ),
                    combined_text_search AS (
                        SELECT id FROM insert_search_text
                        UNION ALL
                        SELECT id FROM update_search_text
                    )
                    SELECT {SCHEMA_NAME}.process_hive_post_mentions(array_agg(id))
                    FROM combined
                    UNION ALL
                    SELECT id FROM combined_text_search
        """
        if print_query:
            log.info(f"Executing query:\n{sql}")
        cls.db.query_prepared(sql)
        cls.db.query_no_return("SET auto_explain.log_min_duration=1000")
        values_insert.clear()
        values_update.clear()

        cls.commitTx()

        n = len(cls._data.keys())
        cls._data.clear()
        return n

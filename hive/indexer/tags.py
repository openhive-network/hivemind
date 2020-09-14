import logging
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

from hive.utils.normalize import escape_characters

class Tags(DbAdapterHolder):
    """ Tags cache """
    _tags = []

    @classmethod
    def add_tag(cls, tid, tag, bn):
        """ Add tag to cache """
        cls._tags.append((tid, tag, bn))

    @classmethod
    def flush(cls):
        """ Flush tags to table """
        if cls._tags:
            cls.beginTx()
            limit = 1000

            sql = """
                INSERT INTO
                    hive_tag_data (tag)
                VALUES {} 
                ON CONFLICT DO NOTHING
            """
            values = []
            for tag in cls._tags:
                values.append(f"({escape_characters(tag[1])} /* block number: {tag[2]} */)")
                if len(values) >= limit:
                    tag_query = str(sql)
                    cls.db.query(tag_query.format(','.join(values)))
                    values.clear()
            if len(values) > 0:
                tag_query = str(sql)
                cls.db.query(tag_query.format(','.join(values)))
                values.clear()

            sql = """
                INSERT INTO
                    hive_post_tags (post_id, tag_id)
                SELECT 
                    data_source.post_id, data_source.tag_id
                FROM
                (
                    SELECT 
                        post_id, htd.id
                    FROM
                    (
                        VALUES 
                            {}
                    ) AS T(post_id, tag)
                    INNER JOIN hive_tag_data htd ON htd.tag = T.tag
                ) AS data_source(post_id, tag_id)
                ON CONFLICT DO NOTHING
            """
            values = []
            for tag in cls._tags:
                values.append("({}, {} /* block number: {} */)".format(tag[0], escape_characters(tag[1]), tag[2]))
                if len(values) >= limit:
                    tag_query = str(sql)
                    cls.db.query(tag_query.format(','.join(values)))
                    values.clear()
            if len(values) > 0:
                tag_query = str(sql)
                cls.db.query(tag_query.format(','.join(values)))
                values.clear()
            cls.commitTx()
        n = len(cls._tags)
        cls._tags.clear()
        return n

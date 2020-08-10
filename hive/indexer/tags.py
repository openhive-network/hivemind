import logging
from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

from hive.utils.normalize import escape_characters

class Tags(object):
    """ Tags cache """
    _tags = []

    @classmethod
    def add_tag(cls, tid, tag):
        """ Add tag to cache """
        cls._tags.append((tid, tag))

    @classmethod
    def flush(cls):
        """ Flush tags to table """
        if cls._tags:
            limit = 1000

            sql = """
                INSERT INTO
                    hive_tag_data (tag)
                VALUES {} 
                ON CONFLICT DO NOTHING
            """
            values = []
            for tag in cls._tags:
                values.append("({})".format(escape_characters(tag[1])))
                if len(values) >= limit:
                    tag_query = str(sql)
                    DB.query(tag_query.format(','.join(values)))
                    values.clear()
            if len(values) > 0:
                tag_query = str(sql)
                DB.query(tag_query.format(','.join(values)))
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
                values.append("({}, {})".format(tag[0], escape_characters(tag[1])))
                if len(values) >= limit:
                    tag_query = str(sql)
                    DB.query(tag_query.format(','.join(values)))
                    values.clear()
            if len(values) > 0:
                tag_query = str(sql)
                DB.query(tag_query.format(','.join(values)))
                values.clear()
            
        n = len(cls._tags)
        cls._tags.clear()
        return n

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
            sql = """
                INSERT INTO
                    hive_tag_data (tag)
                VALUES 
            """
            values = []
            for tag in cls._tags:
                values.append("('{}')".format(escape_characters(tag[1])))
            sql += ",".join(values)
            sql += " ON CONFLICT DO NOTHING;"

            sql += """
                INSERT INTO
                    hive_post_tags (post_id, tag_id)
                VALUES 
            """
            values = []
            for tag in cls._tags:
                values.append("({}, (SELECT id FROM hive_tag_data WHERE tag='{}'))".format(tag[0], escape_characters(tag[1])))
            sql += ",".join(values)
            sql += " ON CONFLICT DO NOTHING"
            DB.query(sql)
            cls._tags.clear()

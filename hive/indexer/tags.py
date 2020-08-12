import logging
from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

from hive.utils.normalize import escape_characters

class Tags(object):
    """ Tags cache """
    _tags = {}

    @classmethod
    def add_tag(cls, tid, tag):
        """ Add tag to cache """
        if tid in cls._tags:
          cls._tags[tid].append(tag)
        else:
          cls._tags[tid]=[]
          cls._tags[tid].append(tag)

    @classmethod
    def write_data_into_db_before_post_deleting(cls, pid):
      _tmp_data = {}

      #Extract data for given key
      _tmp_data[pid] = cls._tags[pid]

      #Remove from original dictionary
      del cls._tags[pid]

      #Save into database
      cls.flush_from_source(_tmp_data)

    @classmethod
    def flush_from_source(cls, source):
        """ Flush tags to table """
        if source:
            limit = 1000

            sql = """
                INSERT INTO
                    hive_tag_data (tag)
                VALUES {} 
                ON CONFLICT DO NOTHING
            """
            values = []
            for id,value in source.items():
              for tag in value:
                values.append("({})".format(escape_characters(tag)))
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
            for id,value in source.items():
              for tag in value:
                values.append("({}, {})".format(id, escape_characters(tag)))
                if len(values) >= limit:
                    tag_query = str(sql)
                    DB.query(tag_query.format(','.join(values)))
                    values.clear()
            if len(values) > 0:
                tag_query = str(sql)
                DB.query(tag_query.format(','.join(values)))
                values.clear()
            source.clear()

    @classmethod
    def flush(cls):
      cls.flush_from_source(cls._tags)

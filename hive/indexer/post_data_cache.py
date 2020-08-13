import logging
from hive.utils.normalize import escape_characters
from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

class PostDataCache(object):
    """ Procides cache for DB operations on post data table in order to speed up initial sync """
    _data = {}

    @classmethod
    def is_cached(cls, pid):
        """ Check if data is cached """
        return pid in cls._data

    @classmethod
    def add_data(cls, pid, post_data, print_query = False):
        """ Add data to cache """
        cls._data[pid] = post_data

    @classmethod
    def get_post_body(cls, pid):
        """ Returns body of given post from collected cache or from underlying DB storage. """
        try:
            post_data = cls._data[pid]
        except KeyError:
            sql = """
                  SELECT hpd.body FROM hive_post_data hpd WHERE hpd.id = :post_id;
                  """
            row = DB.query_row(sql, post_id = pid)
            post_data = dict(row)
        return post_data['body']

    @classmethod
    def write_data_into_db_before_post_deleting(cls, pid, print_query = False):
      if pid not in cls._data:
        return

      _tmp_data = {}

      #Extract data for given key
      _tmp_data[pid] = cls._data[pid]

      #Save into database
      cls.flush_from_source(_tmp_data, True, print_query)

      #Remove from original dictionary
      del cls._data[pid]

    @classmethod
    def flush_from_source(cls, source, deleted_mode, print_query = False):
        """ Flush data from cache to db """
        if source:
            sql = ""
            if deleted_mode:
              sql = """
                INSERT INTO 
                    deleted_hive_post_data (id, title, preview, img_url, body, json) 
                VALUES 
            """
            else:
              sql = """
                INSERT INTO 
                    hive_post_data (id, title, preview, img_url, body, json) 
                VALUES 
              """
            values = []
            for k, data in source.items():
                title = "''" if not data['title'] else "{}".format(escape_characters(data['title']))
                preview = "''" if not data['preview'] else "{}".format(escape_characters(data['preview']))
                img_url = "''" if not data['img_url'] else "{}".format(escape_characters(data['img_url']))
                body = "''" if not data['body'] else "{}".format(escape_characters(data['body']))
                json = "'{}'" if not data['json'] else "{}".format(escape_characters(data['json']))
                values.append("({},{},{},{},{},{})".format(k, title, preview, img_url, body, json))
            sql += ','.join(values)
            sql += """
                ON CONFLICT (id)
                    DO
                        UPDATE SET 
                            title = EXCLUDED.title,
                            preview = EXCLUDED.preview,
                            img_url = EXCLUDED.img_url,
                            body = EXCLUDED.body,
                            json = EXCLUDED.json
                        WHERE
                            hive_post_data.id = EXCLUDED.id
            """

            if(print_query):
                log.info("Executing query:\n{}".format(sql))

            DB.query(sql)
            source.clear()

    @classmethod
    def flush(cls, print_query = False):
      cls.flush_from_source(cls._data, False, print_query)
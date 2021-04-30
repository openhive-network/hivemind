import logging
from hive.utils.normalize import escape_characters

from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.misc import deep_clear

log = logging.getLogger(__name__)

class PostDataCache(DbAdapterHolder):
    """ Procides cache for DB operations on post data table in order to speed up initial sync """
    _data = {}


    @classmethod
    def is_cached(cls, pid):
        """ Check if data is cached """
        return pid in cls._data

    @classmethod
    def add_data(cls, pid, post_data, is_new_post):
        """ Add data to cache """
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
        """ Returns body of given post from collected cache or from underlying DB storage. """
        try:
            post_data = cls._data[pid]
        except KeyError:
            sql = """
                  SELECT hpd.body FROM hive_post_data hpd WHERE hpd.id = :post_id;
                  """
            row = cls.db.query_row(sql, post_id = pid)
            post_data = dict(row)
        return post_data['body']

    @classmethod
    def flush(cls, print_query = False):
        """ Flush data from cache to db """
        if cls._data:
            values_insert = []
            values_update = []
            cls.beginTx()
            sql = """
                INSERT INTO 
                    hive_post_data (id, title, preview, img_url, body, json) 
                VALUES 
            """
            values = []
            for k, data in cls._data.items():
                title = 'NULL' if data['title'] is None else "{}".format(escape_characters(data['title']))
                body = 'NULL' if data['body'] is None else "{}".format(escape_characters(data['body']))
                preview = 'NULL' if data['body'] is None else "{}".format(escape_characters(data['body'][0:1024]))
                json = 'NULL' if data['json'] is None else "{}".format(escape_characters(data['json']))
                img_url = 'NULL' if data['img_url'] is None else "{}".format(escape_characters(data['img_url']))
                value = "({},{},{},{},{},{})".format(k, title, preview, img_url, body, json)
                if data['is_new_post']:
                    values_insert.append(value)
                else:
                    values_update.append(value)

            if values_insert:
                sql = """
                    INSERT INTO 
                        hive_post_data (id, title, preview, img_url, body, json) 
                    VALUES 
                """
                sql += ','.join(values_insert)
                if print_query:
                    log.info("Executing query:\n{}".format(sql))
                cls.db.query(sql)

            if values_update:
                sql = """
                    UPDATE hive_post_data AS hpd SET 
                        title = COALESCE( data_source.title, hpd.title ),
                        preview = COALESCE( data_source.preview, hpd.preview ),
                        img_url = COALESCE( data_source.img_url, hpd.img_url ),
                        body = COALESCE( data_source.body, hpd.body ),
                        json = COALESCE( data_source.json, hpd.json )
                    FROM
                    ( SELECT * FROM
                    ( VALUES
                """
                sql += ','.join(values_update)
                sql += """
                    ) AS T(id, title, preview, img_url, body, json)
                    ) AS data_source
                    WHERE hpd.id = data_source.id
                """
                if print_query:
                    log.info("Executing query:\n{}".format(sql))
                cls.db.query(sql)

            cls.commitTx()

        n = len(cls._data.keys())
        cls._data = deep_clear(cls._data)
        return n

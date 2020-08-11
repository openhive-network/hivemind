import math
import decimal

from hive.db.adapter import Db

DB = Db.instance()

def update_all_hot_and_tranding():
    """Calculate and set hot and trending values of all posts"""
    sql = """
        UPDATE hive_posts ihp
            set sc_hot = calculate_hot(ds.rshares_sum, ihp.created_at),
            sc_trend = calculate_tranding(ds.rshares_sum, ihp.created_at)
        FROM
        (
            SELECT hv.post_id as id, CAST(sum(hv.rshares) AS BIGINT) as rshares_sum
            FROM hive_votes hv
            group by hv.post_id
        ) as ds
        WHERE ihp.id = ds.id
    """
    DB.query_no_return(sql)


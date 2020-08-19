import math
import decimal


from hive.db.adapter import Db

DB = Db.instance()

def update_all_hot_and_tranding():
    """Calculate and set hot and trending values of all posts"""
    update_hot_and_tranding_for_block_range()

NO_CONSTRAINT = -1

def update_hot_and_tranding_for_block_range( first_block = NO_CONSTRAINT, last_block = NO_CONSTRAINT):
    """Calculate and set hot and trending values of all posts"""
    hot_and_trend_sql = """
        UPDATE hive_posts ihp
            set sc_hot = calculate_hot(ds.rshares_sum, ihp.created_at),
            sc_trend = calculate_tranding(ds.rshares_sum, ihp.created_at)
        FROM
        (
            SELECT hv.post_id as id, CAST(sum(hv.rshares) AS BIGINT) as rshares_sum
            FROM hive_votes hv
            {}
            GROUP BY hv.post_id
        ) as ds
        WHERE ihp.id = ds.id
    """

    sql = ""
    if first_block == NO_CONSTRAINT and last_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format( "" )
    elif last_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format( "WHERE block_num >= {}".format( first_block ) )
    elif first_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format( "WHERE block_num <= {}".format( last_block ) )
    else:
        sql = hot_and_trend_sql.format( "WHERE block_num >= {} AND block_num <= {}".format( first_block, last_block ) )
    DB.query_no_return(sql)

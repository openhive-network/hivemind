from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.utils.timer import time_it

DB = Db.instance()


def update_all_hot_and_trending():
    """Calculate and set hot and trending values of all posts"""
    # NOT USED!!!
    update_hot_and_trending_for_block_range()


NO_CONSTRAINT = -1


@time_it
def update_hot_and_trending_for_block_range(first_block=NO_CONSTRAINT, last_block=NO_CONSTRAINT):
    """Calculate and set hot and trending values of all posts"""
    # NOT USED!!!
    hot_and_trend_sql = f"""
        UPDATE {SCHEMA_NAME}.hive_posts ihp
            set sc_hot = {SCHEMA_NAME}.calculate_hot(ds.rshares_sum, ihp.created_at),
            sc_trend = {SCHEMA_NAME}.calculate_trending(ds.rshares_sum, ihp.created_at)
        FROM
        (
            SELECT hv.post_id as id, CAST(sum(hv.rshares) AS BIGINT) as rshares_sum
            FROM {SCHEMA_NAME}.hive_votes hv
            {{}}
            GROUP BY hv.post_id
        ) as ds
        WHERE ihp.id = ds.id AND ihp.is_paidout = False
    """

    sql = ""
    if first_block == NO_CONSTRAINT and last_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format("")
    elif last_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format(f"WHERE block_num >= {first_block}")
    elif first_block == NO_CONSTRAINT:
        sql = hot_and_trend_sql.format(f"WHERE block_num <= {last_block}")
    elif first_block == last_block:
        sql = hot_and_trend_sql.format(f"WHERE block_num = {last_block}")
    else:
        sql = hot_and_trend_sql.format(f"WHERE block_num >= {first_block} AND block_num <= {last_block}")
    DB.query_no_return(sql)

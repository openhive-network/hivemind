import math
import decimal

from hive.db.adapter import Db

DB = Db.instance()

def update_all_hot_and_tranding():
    """Calculate and set hot and trending values of all posts"""
    sql = """
        UPDATE hive_posts
        SET (sc_hot,sc_trend)=
            (
                SELECT * FROM calculate_hot_and_tranding(
                (
                    SELECT COALESCE(SUM(rshares),0)
                    FROM hive_votes
	                WHERE post_id=hive_posts.id
                 )
                 , created_at
             )
	    )
        WHERE id > 0
        """
    DB.query_no_return(sql)



def update_hot_and_tranding( author, permlink ):
    """Calculate and set hot and trending values of a post"""
    sql = """
        SELECT update_post_hot_and_trend( '{}', '{}' )
        """.format(author, permlink)
    DB.query_no_return(sql)

def score(rshares, created_timestamp, timescale=480000):
    """Calculate trending/hot score.

    Source: calculate_score - https://github.com/steemit/steem/blob/8cd5f688d75092298bcffaa48a543ed9b01447a6/libraries/plugins/tags/tags_plugin.cpp#L239
    """
    mod_score = decimal.Decimal(rshares) / decimal.Decimal(10000000.0)
    order = math.log10(max((abs(mod_score), 1)))
    sign = 1 if mod_score > 0 else -1
    return sign * order + created_timestamp / timescale

from hive.db.adapter import Db
from hive.db.db_state import DbState

class HotAndTrendBatchUpdater:
    author_permlink_batch = []

    @classmethod
    def append_post(cls, author, permlink ):
        """Collect posts to commit"""
        if not DbState.is_initial_sync():
            cls.author_permlink_batch.append( "('{}','{}')".format( author, permlink ) )

    @classmethod
    def commit(cls):
        """Commits collected posts to DB"""
        if not DbState.is_initial_sync():
            posts_str = ','.join(cls.author_permlink_batch)

            sql ="""
                UPDATE hive_posts
                SET
            	    (sc_hot,sc_trend) = ( SELECT (result).hot, (result).trend FROM
                        (SELECT calculate_hot_and_tranding(sum_of_rshares, created_at) as result, post_id FROM
                	          (SELECT sum_of_rshares, hp.created_at as created_at,hp.id as post_id FROM
                		            (SELECT post_id, COALESCE(SUM(rshares),0) as sum_of_rshares
                		             FROM hive_votes_accounts_permlinks_view as hv
                		             INNER JOIN (VALUES {}) AS t(author,permlink)
                			         ON hv.author=t.author and hv.permlink=t.permlink GROUP BY post_id
                                     ) as votes_rshares
    		                   INNER JOIN hive_posts as hp ON votes_rshares.post_id = hp.id
            	              ) as post_rshares
                          ) as hot_and_trend_ad_post
            WHERE hot_and_trend_ad_post.post_id = hive_posts.id )
            """
            DB.query_no_return(sql)

        cls.author_permlink_batch.clear()

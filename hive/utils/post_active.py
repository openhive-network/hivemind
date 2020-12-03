from hive.db.adapter import Db
from hive.utils.timer import time_it

DB = Db.instance()
"""
There are three cases when 'active' field in post is updated:
1) when a descendant post comment was added (recursivly on any depth)
2) when a descendant post comment was deleted (recursivly on any depth)
3) when the post is updated - that one only updates that post active (not here)

It means that, when the comment for posts is updated then its 'active' field
does not propagate for its ancestors.
"""

update_active_sql = """
    WITH RECURSIVE parent_posts ( parent_id, post_id, intrusive_active ) AS (
      SELECT
        hp1.parent_id as parent_id,
        hp1.id as post_id,
        CASE WHEN hp1.counter_deleted > 0 THEN hp1.active
        ELSE hp1.created_at
        END as intrusive_active
      FROM hive_posts hp1
      WHERE hp1.depth > 0 {}
      UNION
      SELECT
        hp2.parent_id as parent_id,
        hp2.id as post_id,
        max_time_stamp(
          CASE WHEN hp2.counter_deleted > 0 THEN hp2.active
          ELSE hp2.created_at
          END
          , pp.intrusive_active
        ) as intrusive_active
      FROM parent_posts pp
      JOIN hive_posts hp2 ON pp.parent_id = hp2.id
      WHERE hp2.depth > 0
    )
    UPDATE
      hive_posts
    SET
      active = new_active
    FROM
    (
      SELECT hp.id as post_id, max_time_stamp( hp.active, MAX(pp.intrusive_active) ) as new_active
      FROM parent_posts pp
      JOIN hive_posts hp ON pp.parent_id = hp.id GROUP BY hp.id
    ) as dataset
    WHERE dataset.post_id = hive_posts.id;
    """

def update_all_posts_active():
    DB.query_no_return(update_active_sql.format( "AND ( hp1.children = 0 )" ))

@time_it
def update_active_starting_from_posts_on_block( first_block_num, last_block_num ):
    if first_block_num == last_block_num:
            DB.query_no_return(update_active_sql.format( "AND hp1.block_num = {}" ).format(first_block_num) )
            return
    DB.query_no_return(update_active_sql.format( "AND hp1.block_num >= {} AND hp1.block_num <= {}" ).format(first_block_num, last_block_num) )

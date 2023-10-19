from hive.conf import SCHEMA_NAME


def update_communities_posts_and_rank(db):
    sql = f"SELECT {SCHEMA_NAME}.update_communities_posts_data_and_rank()"
    db.query_no_return(sql)

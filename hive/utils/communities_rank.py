from hive.db.adapter import Db

DB = Db.instance()

def update_communities_posts_and_rank():
    sql = "SELECT update_communities_posts_data_and_rank()"
    DB.query_no_return(sql)

def update_communities_posts_and_rank(db):
    sql = "SELECT update_communities_posts_data_and_rank()"
    db.query_no_return(sql)

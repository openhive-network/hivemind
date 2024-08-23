"""Cursor-based pagination queries, mostly supporting condenser_api."""
from hive.conf import SCHEMA_NAME
from hive.server.condenser_api.objects import _condenser_post_object
from hive.server.database_api.methods import find_votes_impl, VotesPresentation


# pylint: disable=too-many-lines


async def get_followers(db, account: str, start: str, state: int, limit: int):
    """Get a list of accounts following given account."""
    sql = (
        f"SELECT * FROM {SCHEMA_NAME}.condenser_get_followers( (:account)::VARCHAR, (:start)::VARCHAR, :type, :limit )"
    )
    return await db.query_col(sql, account=account, start=start, type=state, limit=limit)


async def get_following(db, account: str, start: str, state: int, limit: int):
    """Get a list of accounts followed by a given account."""
    sql = (
        f"SELECT * FROM {SCHEMA_NAME}.condenser_get_following( (:account)::VARCHAR, (:start)::VARCHAR, :type, :limit )"
    )
    return await db.query_col(sql, account=account, start=start, type=state, limit=limit)


async def get_reblogged_by(db, author: str, permlink: str):
    """Return all rebloggers of a post."""

    sql = f"SELECT * FROM {SCHEMA_NAME}.condenser_get_names_by_reblogged( (:author)::VARCHAR, (:permlink)::VARCHAR )"
    names = await db.query_col(sql, author=author, permlink=permlink)

    if author in names:
        names.remove(author)
    return names


async def process_posts(db, sql_result, truncate_body: int = 0):
    posts = []
    for row in sql_result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)

        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        posts.append(post)

    return posts


async def get_by_blog_without_reblog(
    db, account: str, start_permlink: str = '', limit: int = 20, truncate_body: int = 0
):
    """Get a list of posts for an author's blog without reblogs."""
    sql = f"SELECT * FROM {SCHEMA_NAME}.condenser_get_by_blog_without_reblog( (:author)::VARCHAR, (:permlink)::VARCHAR, :limit )"
    result = await db.query_all(sql, author=account, permlink=start_permlink, limit=limit)
    return await process_posts(db, result, truncate_body)


async def get_by_account_comments(db, account: str, start_permlink: str = '', limit: int = 20, truncate_body: int = 0):
    """Get a list of posts representing comments by an author."""
    sql = f"SELECT * FROM {SCHEMA_NAME}.condenser_get_by_account_comments( (:author)::VARCHAR, (:permlink)::VARCHAR, :limit )"
    result = await db.query_all(sql, author=account, permlink=start_permlink, limit=limit)
    return await process_posts(db, result, truncate_body)


async def get_by_replies_to_account(
    db, start_author: str, start_permlink: str = '', limit: int = 20, truncate_body: int = 0, observer: str = ''
):
    """Get a list of posts representing replies to an author."""
    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_replies( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR, False )"
    result = await db.query_all(
        sql, account=start_author, author=start_author if start_permlink else '', permlink=start_permlink, limit=limit, observer=observer
    )
    return await process_posts(db, result, truncate_body)


async def get_by_blog(db, account: str = '', start_author: str = '', start_permlink: str = '', limit: int = 20):
    """Get a list of posts for an author's blog."""
    sql = f"SELECT * FROM {SCHEMA_NAME}.condenser_get_by_blog( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, :limit )"
    result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit)
    return await process_posts(db, result)

"""Hive API: Internal supporting methods"""
import logging

log = logging.getLogger(__name__)

async def get_community_id(db, name):
    """Get community id from db."""
    return await db.query_one("SELECT find_community_id( (:name)::VARCHAR, True )", name=name)

async def get_account_id(db, name):
    """Get account id from account name."""
    return await db.query_one("SELECT find_account_id( (:name)::VARCHAR, True )", name=name)

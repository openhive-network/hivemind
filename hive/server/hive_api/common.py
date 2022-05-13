"""Hive API: Internal supporting methods"""
import logging

from hive.conf import SCHEMA_NAME

log = logging.getLogger(__name__)


async def get_community_id(db, name):
    """Get community id from db."""
    assert name, 'community name cannot be blank'
    return await db.query_one(f"SELECT {SCHEMA_NAME}.find_community_id( (:name)::VARCHAR, True )", name=name)


async def get_account_id(db, name):
    """Get account id from account name."""
    return await db.query_one(f"SELECT {SCHEMA_NAME}.find_account_id( (:name)::VARCHAR, True )", name=name)

import logging

from hive.conf import SCHEMA_NAME, REPTRACKER_SCHEMA_NAME, ONE_WEEK_IN_BLOCKS
from hive.db.adapter import Db

log = logging.getLogger(__name__)


def prepare_app_context(db: Db) -> None:
    log.info(f"Looking for '{SCHEMA_NAME}' and '{REPTRACKER_SCHEMA_NAME}' contexts.")
    ctx_present = db.query_one(f"SELECT hive.app_context_exists('{SCHEMA_NAME}') as ctx_present;")
    if not ctx_present:
        LIMIT_FOR_PROCESSED_BLOCKS = 1000
        synchronization_stages = f"""ARRAY[
              hive.stage( 'MASSIVE_WITHOUT_INDEXES', {ONE_WEEK_IN_BLOCKS}, {LIMIT_FOR_PROCESSED_BLOCKS}, '20 seconds' )
            , hive.stage( 'MASSIVE_WITH_INDEXES', 101, {LIMIT_FOR_PROCESSED_BLOCKS}, '20 seconds' )
            , hive.live_stage()
        ]::hive.application_stages"""
        log.info(f"No application context present. Attempting to create a '{SCHEMA_NAME}' context...")
        db.query_no_return(f"SELECT hive.app_create_context('{SCHEMA_NAME}', '{SCHEMA_NAME}', _is_forking => FALSE, _stages => {synchronization_stages} );") #is-forking=FALSE, only process irreversible blocks
        log.info("Application context creation done.")
    else:
        log.info(f"Found existing context, set to non-forking.")
        db.query_no_return(f"SELECT hive.app_context_set_non_forking('{SCHEMA_NAME}');") #if existing context, make it non-forking
        is_forking = db.query_one(f"SELECT hive.app_is_forking('{SCHEMA_NAME}') as is_forking;")
        log.info(f"is_forking={is_forking}")


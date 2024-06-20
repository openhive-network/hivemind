import logging

from hive.conf import SCHEMA_NAME, ONE_WEEK_IN_BLOCKS
from hive.db.adapter import Db

log = logging.getLogger(__name__)


def prepare_app_context(db: Db) -> None:
    log.info(f"Looking for '{SCHEMA_NAME}' context.")
    ctx_present = db.query_one(f"SELECT hive.app_context_exists('{SCHEMA_NAME}') as ctx_present;")
    if not ctx_present:
        LIMIT_FOR_PROCESSED_BLOCKS = 1000
        synchronization_stages = f"""ARRAY[
              ( 'MASSIVE_WITHOUT_INDEXES', {ONE_WEEK_IN_BLOCKS}, {LIMIT_FOR_PROCESSED_BLOCKS} )
            , ( 'MASSIVE_WITH_INDEXES', 101, {LIMIT_FOR_PROCESSED_BLOCKS} )
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



def context_detach(db: Db) -> None:
    is_attached = db.query_one(f"SELECT hive.app_context_is_attached('{SCHEMA_NAME}')")

    if not is_attached:
        log.info("No attached context - detach skipped.")
        return

    log.info("Trying to detach app context...")
    db.query_no_return(f"SELECT hive.app_context_detach('{SCHEMA_NAME}')")
    log.info("App context detaching done.")


def context_attach(db: Db) -> None:
    is_attached = db.query_one(f"SELECT hive.app_context_is_attached('{SCHEMA_NAME}')")
    if is_attached:
        #Update last_active_at to avoid context being detached by auto-detacher prior to call to next_app_block.
        #This is a workaround for current flaws in transaction management in hivemind, so it can be removed
        #once transaction management is properly done (i.e. transactions should start/end when hivemind is consistent with a block)
        db.query_no_return(f"SELECT hive.app_update_last_active_at('{SCHEMA_NAME}')");
        log.info("Context already attached - attaching skipped, but last_active_at updated.")
        return

    db.query_no_return(f"CALL hive.appproc_context_attach('{SCHEMA_NAME}')")
    log.info("App context attaching done.")

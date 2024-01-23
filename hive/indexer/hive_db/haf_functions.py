import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db

log = logging.getLogger(__name__)


def prepare_app_context(db: Db) -> None:
    log.info(f"Looking for '{SCHEMA_NAME}' context.")
    ctx_present = db.query_one(f"SELECT hive.app_context_exists('{SCHEMA_NAME}') as ctx_present;")
    if not ctx_present:
        log.info(f"No application context present. Attempting to create a '{SCHEMA_NAME}' context...")
        db.query_no_return(f"SELECT hive.app_create_context('{SCHEMA_NAME}', true, true);")
        log.info("Application context creation done.")


def context_detach(db: Db) -> None:
    is_attached = db.query_one(f"SELECT hive.app_context_is_attached('{SCHEMA_NAME}')")

    if not is_attached:
        log.info("No attached context - detach skipped.")
        return

    log.info("Trying to detach app context...")
    db.query_no_return(f"CALL hive.appproc_context_detach('{SCHEMA_NAME}')")
    log.info("App context detaching done.")


def context_attach(db: Db, block_number: int) -> None:
    is_attached = db.query_one(f"SELECT hive.app_context_is_attached('{SCHEMA_NAME}')")

    if is_attached:
        log.info("Context already attached - attaching skipped.")
        return

    log.info(f"Trying to attach app context with block number: {block_number}")
    db.query_no_return(f"CALL hive.appproc_context_attach('{SCHEMA_NAME}', {block_number})")
    log.info("App context attaching done.")

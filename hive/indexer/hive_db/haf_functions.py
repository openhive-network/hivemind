import logging

from hive.conf import ONE_WEEK_IN_BLOCKS, REPTRACKER_SCHEMA_NAME, SCHEMA_NAME
from hive.db.adapter import Db

log = logging.getLogger(__name__)

# Custom JSON types that Hivemind processes
HIVEMIND_CUSTOM_JSON_TYPES = ['follow', 'reblog', 'community', 'notify']


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
        db.query_no_return(
            f"SELECT hive.app_create_context('{SCHEMA_NAME}', '{SCHEMA_NAME}', _is_forking => FALSE, _stages => {synchronization_stages} );"
        )  # is-forking=FALSE, only process irreversible blocks
        log.info("Application context creation done.")
    else:
        log.info("Found existing context, set to non-forking.")
        db.query_no_return(
            f"SELECT hive.app_context_set_non_forking('{SCHEMA_NAME}');"
        )  # if existing context, make it non-forking
        is_forking = db.query_one(f"SELECT hive.app_is_forking('{SCHEMA_NAME}') as is_forking;")
        log.info(f"is_forking={is_forking}")

    # Note: custom_json_type index creation is deferred to sync startup
    # (SyncHiveDb.run) so that the install container finishes quickly.


def ensure_custom_json_type_index(db: Db) -> None:
    """Register partial index on hafd.operations for Hivemind's custom_json types.

    Uses hive.register_custom_json_type_index which registers the index via
    register_index_dependency. HAF's indexes_controler then creates it with
    CREATE INDEX CONCURRENTLY, avoiding ShareLock contention with other apps.
    """
    types_array = "ARRAY[" + ",".join(f"'{t}'" for t in HIVEMIND_CUSTOM_JSON_TYPES) + "]"
    log.info(f"Registering custom_json_type index for types: {HIVEMIND_CUSTOM_JSON_TYPES}")
    db.query_no_return(f"SELECT hive.register_custom_json_type_index('{SCHEMA_NAME}', {types_array});")

import logging

from hive.conf import MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS, REPTRACKER_SCHEMA_NAME, SCHEMA_NAME
from hive.db.adapter import Db

log = logging.getLogger(__name__)

# Custom JSON types that Hivemind processes
HIVEMIND_CUSTOM_JSON_TYPES = ['follow', 'reblog', 'community', 'notify']


def prepare_app_context(db: Db) -> None:
    log.info(f"Looking for '{SCHEMA_NAME}' and '{REPTRACKER_SCHEMA_NAME}' contexts.")
    ctx_present = db.query_one(f"SELECT hive.app_context_exists('{SCHEMA_NAME}') as ctx_present;")
    if not ctx_present:
        LIMIT_FOR_PROCESSED_BLOCKS = 1000
        # Existing contexts get the same stages via the UPDATE in
        # upgrade/upgrade_runtime_migration.sql — keep the two in sync.
        synchronization_stages = f"""ARRAY[
              hive.stage( 'MASSIVE_WITHOUT_INDEXES', {MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS}, {LIMIT_FOR_PROCESSED_BLOCKS}, '20 seconds' )
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

    # Registration in the HAF application registry (register_application) is
    # done by setup_runtime_code, after the runtime SQL it depends on exists.

    # Note: custom_json_type index creation is deferred to sync startup
    # (SyncHiveDb.run) so that the install container finishes quickly.


def register_application(db: Db) -> None:
    """Register hivemind in the HAF application registry (haf#341).

    Hivemind drives its own loop (no process procedure), so the registration
    exists for other applications: hivesense and proxy-whitelist declare a
    dependency on 'hivemind_app', and HAF then withholds from them every block
    hivemind has not committed yet.

    That gating normally reads a dependency's hafd.contexts.current_block_num,
    which is right for loops that commit the position together with the block's
    work - hivemind's live sync does (#336). Massive sync however commits the
    position (and the _batch_queue crash-recovery marker) BEFORE the batch is
    flushed on the massive connection, so the committed data trails the position
    by the in-flight batch: completed_block_num() reports the position minus
    that batch, and is registered as the completed-block function.
    """
    db.query_no_return(
        f"""CREATE OR REPLACE FUNCTION {SCHEMA_NAME}.completed_block_num()
            RETURNS INTEGER
            LANGUAGE sql
            STABLE
            AS $$
                SELECT LEAST(
                    hive.app_get_current_block_num('{SCHEMA_NAME}'),
                    COALESCE((SELECT MIN(first_block) - 1 FROM {SCHEMA_NAME}._batch_queue), 2147483647)
                )
            $$;"""
    )
    registry_available = db.query_one("SELECT to_regprocedure('hive.app_register(text, hive.contexts_group, text, text)') IS NOT NULL")
    if not registry_available:
        log.warning("HAF application registry not available (hive.app_register); skipping hivemind registration")
        return
    db.query_no_return(
        f"SELECT hive.app_register('{SCHEMA_NAME}', ARRAY['{SCHEMA_NAME}']::hive.contexts_group, NULL, '{SCHEMA_NAME}.completed_block_num');"
    )
    log.info(f"Registered '{SCHEMA_NAME}' in the HAF application registry (self-driven, completed block via {SCHEMA_NAME}.completed_block_num)")


def ensure_custom_json_type_index(db: Db) -> None:
    """Create partial index on hafd.operations for Hivemind's custom_json types."""
    from time import perf_counter

    types_array = "ARRAY[" + ",".join(f"'{t}'" for t in HIVEMIND_CUSTOM_JSON_TYPES) + "]"
    log.info(f"Creating custom_json_type index for types: {HIVEMIND_CUSTOM_JSON_TYPES} ...")
    t0 = perf_counter()
    db.query_no_return(f"SELECT hive.create_custom_json_type_index({types_array});")
    elapsed = perf_counter() - t0
    log.info(f"custom_json_type index ready in {elapsed:.1f}s")

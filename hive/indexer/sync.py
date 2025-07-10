"""Hive sync manager."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import logging
import time
from time import perf_counter as perf
from typing import Iterable, Tuple

from hive.conf import Conf, SCHEMA_NAME
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.accounts import Accounts
from hive.indexer.block import BlocksProviderBase
from hive.indexer.blocks import Blocks
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbLiveContextHolder
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.utils.payout_stats import PayoutStats
from hive.signals import (
    can_continue_thread,
    restore_default_signal_handlers,
    set_custom_signal_handlers,
    set_exception_thrown,
)
from hive.utils.misc import log_memory_usage
from hive.utils.normalize import secs_to_str
from hive.utils.stats import BroadcastObject
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.stats import PrometheusClient as PC
from hive.utils.stats import WaitingStatusManager as WSM
from hive.utils.timer import Timer

import ast

log = logging.getLogger(__name__)


class SyncHiveDb:
    def __init__(self, conf: Conf, enter_sync: bool, upgrade_schema: bool):
        self._conf = conf
        self._db = conf.db()
        self._enter_sync = enter_sync
        self._upgrade_schema = upgrade_schema

        # Might be lower or higher than actual block number stored in HAF database
        self._last_block_to_process = self._conf.get('test_max_block')
        self._max_batch = conf.get('max_batch')

        self._massive_blocks_data_provider = None
        self._lbound = None
        self._ubound = None
        self._databases = None
        self.time_start = None

        self._massive_consume_blocks_futures = None
        self._massive_consume_blocks_thread_pool = ThreadPoolExecutor(max_workers=1)
        self.rate = {}

    def __enter__(self):
        if self._enter_sync:
            log.info("Entering HAF mode synchronization")

        set_custom_signal_handlers()

        Community.start_block = self._conf.get("community_start_block")
        DbState.initialize(self._enter_sync, self._upgrade_schema)

        Blocks.setup(conf=self._conf)

        self._show_info(self._db)

        self._check_log_explain_queries()

        if self._enter_sync:
            Accounts.load_ids()  # prefetch id->name and id->rank memory maps

        return self

    def __exit__(self, exc_type, value, traceback):
        if self._enter_sync:
            log.info("Exiting HAF mode synchronization")

            PayoutStats.generate(self._db, separate_transaction=True)

            last_imported_block = Blocks.last_imported()
            log.info(f'LAST IMPORTED BLOCK IS: {last_imported_block}')
            log.info(f'LAST COMPLETED BLOCK IS: {Blocks.last_completed()}')

            Blocks.close_own_db_access()

        if self._databases:
            self._databases.close()

    def build_database_schema(self) -> None:
        # whole code building it is already placed inside __enter__ handler, here was added only explicit messaging
        log.info("Attempting to build Hivemind database schema if needed")

    def run(self) -> None:
        start_time = perf()

        def report_enter_to_stage(current_stage) -> bool:
            if report_enter_to_stage.prev_application_stage is None or report_enter_to_stage.prev_application_stage != current_stage:
                last_imported = self._db.query_one(f"SELECT hive.app_get_current_block_num( '{SCHEMA_NAME}' );")
                log.info(f"Switched to `{current_stage}` mode | block: {last_imported} | processing time: {secs_to_str(perf() - start_time)}")
                report_enter_to_stage.prev_application_stage = current_stage
                return True
            report_enter_to_stage.prev_application_stage = current_stage
            return False

        report_enter_to_stage.prev_application_stage = None
        log.info(f"Using HAF database as block data provider, pointed by url: '{self._conf.get('database_url')}'")

        self._massive_blocks_data_provider = None
        active_connections_before = self._get_active_db_connections()
        SyncHiveDb.time_start = OPSM.start()

        self._create_massive_provider_if_no_exist()
        while True:
            last_imported_block = Blocks.last_imported()
            log.info(f"Last imported block is: {last_imported_block}")

            # SqlAlchemy will not use autocommit when there is a pending transaction
            # hive.app_next_iteration issues COMMIT, and autocommit is not desired
            # because it save current block before the decision if new range of blocks will be processed or not
            if self._db.is_trx_active():
                self._db.query_no_return( "COMMIT" )
            self._db.query_no_return( "START TRANSACTION" )
            self._lbound, self._ubound = self._query_for_app_next_block()

            application_stage = self._db.query_one(f"SELECT hive.get_current_stage_name('{SCHEMA_NAME}')")

            if self._break_requested(last_imported_block, active_connections_before):
                return

            if self._lbound is None:
                if application_stage == 'wait_for_haf':
                    report_enter_to_stage(application_stage)
                continue

            log.info(f"target_head_block: {self._ubound}")
            log.info(f"test_max_block: {self._last_block_to_process}")

            # this  commit is added here only to prevent error idle-in-transaction timeout
            # it should be removed, but it requires to check any possible long-lasting actions
            # so as quic workaround this COMMIT stays
            self._db.query_no_return( "COMMIT" )
            if application_stage == "MASSIVE_WITHOUT_INDEXES":
                DbState.set_massive_sync( True )
                report_enter_to_stage(application_stage)

                DbState.ensure_off_synchronous_commit()
                DbState.ensure_fk_are_disabled()
                DbState.ensure_indexes_are_disabled()

                self._process_massive_blocks(self._lbound, self._ubound, active_connections_before)
            elif application_stage == "MASSIVE_WITH_INDEXES":
                DbState.set_massive_sync( True )
                if report_enter_to_stage(application_stage):
                    self.print_summary()

                DbState.ensure_off_synchronous_commit()

                DbState.ensure_fk_are_disabled()
                DbState.ensure_indexes_are_enabled()

                self._process_massive_blocks(self._lbound, self._ubound, active_connections_before)
            elif application_stage == "live":
                DbState.set_massive_sync( False )
                report_enter_to_stage(application_stage)

                DbState.ensure_on_synchronous_commit()
                DbState.ensure_indexes_are_enabled()

                if DbState.ensure_finalize_massive_sync(last_imported_block, Blocks.last_completed()):
                    self.print_summary()

                DbState.ensure_fk_are_enabled()

                log.info("[SINGLE] *** SINGLE block processing***")
                log.info(f"[SINGLE] Current system time: {datetime.now().isoformat(sep=' ', timespec='milliseconds')}")

                self._process_live_blocks(self._lbound, self._ubound, active_connections_before)
            else:
                self._on_stop_synchronization(active_connections_before)
                assert False, f"Unknown application stage {application_stage}"

    def _wait_for_massive_consume(self):
        if self._massive_consume_blocks_futures is None:
            return

        self._massive_consume_blocks_futures.result()
        self._massive_consume_blocks_futures = None

    def _break_requested(self, last_imported_block, active_connections_before):
        if not can_continue_thread():
            self._wait_for_massive_consume()
            self._db.query_no_return("ROLLBACK")
            restore_default_signal_handlers()
            self._on_stop_synchronization(active_connections_before)
            return True

        if self._last_block_to_process and (last_imported_block >= self._last_block_to_process):
            self._wait_for_massive_consume()
            self._db.query_no_return("ROLLBACK")
            DbState.ensure_finalize_massive_sync(last_imported_block, Blocks.last_completed())
            log.info(f"REACHED test_max_block of {self._last_block_to_process}")
            self._on_stop_synchronization(active_connections_before)
            return True

        return False

    def _query_for_app_next_block(self) -> Tuple[int, int]:
        limit = "NULL"
        batch = "NULL"
        if self._last_block_to_process:
            limit = self._last_block_to_process

        if self._max_batch:
            batch = self._max_batch

        self._wait_for_massive_consume()
        result = self._db.query_one( "CALL hive.app_next_iteration( _contexts => ARRAY['{}' ]::hive.contexts_group, _blocks_range => (0,0), _limit => {}, _override_max_batch => {} )"
                                     .format(SCHEMA_NAME, limit, batch)
                                    )

        self._db._trx_active = True
        (lbound, ubound) = None, None
        if result is None:
            return lbound, ubound

        try:
            blocks_range = ast.literal_eval(result)
        except SyntaxError:  # SqlAlchemy return (,) when OUT _blocks_range == NULL
            return lbound, ubound

        (lbound, ubound) = blocks_range
        log.info(f"Next block range from hive.app_next_iteration is: <{lbound}:{ubound}>")

        return lbound, ubound

    def _process_live_blocks(self, lbound, ubound, active_connections_before):
        log.info(f"[SINGLE] Attempting to process first block in range: <{self._lbound}:{self._ubound}>")
        wait_blocks_time = WSM.start()
        blocks = self._massive_blocks_data_provider.get_blocks(lbound, ubound)
        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        if not DbLiveContextHolder.is_live_context():
            DbLiveContextHolder.set_live_context(True)
            Blocks.close_own_db_access()
            self._wait_for_connections_closed(active_connections_before)
            Blocks.setup_own_db_access(shared_db_adapter=self._db)

        Blocks.process_multi(blocks, is_massive_sync=False)
        active_connections_after_live = self._get_active_db_connections()
        self._assert_connections_closed(active_connections_before, active_connections_after_live)

    def _process_massive_blocks(self, lbound, ubound, active_connections_before):
        wait_blocks_time = WSM.start()
        blocks = self._massive_blocks_data_provider.get_blocks(lbound, ubound)
        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        if DbLiveContextHolder.is_live_context() or DbLiveContextHolder.is_live_context() is None:
            DbLiveContextHolder.set_live_context(False)
            Blocks.setup_own_db_access(shared_db_adapter=self._db)

        self._massive_consume_blocks_futures =\
            self._massive_consume_blocks_thread_pool.submit(self._consume_massive_blocks, blocks)

    def _on_stop_synchronization(self, active_connections_before):
        self.print_summary()

    def _create_massive_provider_if_no_exist(self):
        if not self._massive_blocks_data_provider:
            self._massive_blocks_data_provider = MassiveBlocksDataProviderHiveDb(
                conf=self._conf,
                db_root=self._db
            )

    def _check_log_explain_queries(self) -> None:
        if self._conf.get("log_explain_queries"):
            is_superuser = self._db.query_one("SELECT is_superuser()")
            assert (
                is_superuser
            ), 'The parameter --log_explain_queries=true can be used only when connect to the database with SUPERUSER privileges'

    @staticmethod
    def _show_info(database: Db) -> None:
        from hive.utils.misc import show_app_version, BlocksInfo, PatchLevelInfo

        blocks_info = BlocksInfo(
            last=Blocks.head_num(),
            last_imported=Blocks.last_imported(),
            last_completed=Blocks.last_completed(),
        )

        sql = f"SELECT * FROM {SCHEMA_NAME}.hive_db_patch_level ORDER BY level DESC LIMIT 1"
        patch_level_info = PatchLevelInfo(**database.query_row(sql))

        show_app_version(log, blocks_info, patch_level_info)

    @staticmethod
    def _blocks_data_provider(blocks_data_provider: BlocksProviderBase) -> None:
        try:
            futures = blocks_data_provider.start()

            for future in futures:
                exception = future.exception()
                if exception:
                    raise exception
        except:
            log.exception("Exception caught during fetching blocks data")
            raise

    def print_summary(self):
        if SyncHiveDb.time_start is None:
            return

        stop = OPSM.stop(SyncHiveDb.time_start)
        log.info("=== TOTAL STATS ===")
        wtm = WSM.log_global("Total waiting times")
        ftm = FSM.log_global("Total flush times")
        otm = OPSM.log_global("All operations present in the processed blocks")
        ttm = ftm + otm + wtm
        log.info("Elapsed time: %.4fs. Calculated elapsed time: %.4fs. Difference: %.4fs", stop, ttm, stop - ttm)

        if self.rate:
           log.info(
               "Highest block processing rate: %.4f bps. %d:%d", self.rate['max'], self.rate['max_from'], self.rate['max_to']
           )
           log.info("Lowest block processing rate: %.4f bps. %d:%d", self.rate['min'], self.rate['min_from'], self.rate['min_to'])
        log.info("=== TOTAL STATS ===")
        self.rate = {}

    def _consume_massive_blocks(self, blocks) -> int:
        from hive.utils.stats import minmax

        if not blocks:
            log.info("No blocks to consume")
            return 0

        lbound = blocks[ 0 ]['num']
        ubound = blocks[ -1 ]['num']
        orig_lbound = lbound
        orig_ubound = ubound

        is_debug = log.isEnabledFor(10)
        num = 0

        self.rate = minmax(self.rate, 0, 1.0, 0)

        try:
            Blocks.set_end_of_sync_lib()
            count = len(blocks)
            timer = Timer(count, entity='block', laps=['rps', 'wps'])

            while lbound <= ubound:
                number_of_blocks_to_proceed = ubound - lbound + 1
                time_before_waiting_for_data = perf()

                to = min(lbound + number_of_blocks_to_proceed, ubound + 1)
                timer.batch_start()

                block_start = perf()
                Blocks.process_multi(blocks, True)
                block_end = perf()

                timer.batch_lap()
                timer.batch_finish(len(blocks))
                time_current = perf()

                prefix = (
                    "[MASSIVE]"
                    f" Got block {min(lbound + number_of_blocks_to_proceed - 1, ubound)} @ {blocks[-1]['date']}"
                )

                log.info(timer.batch_status(prefix))
                log.info(f"[MASSIVE] Time elapsed: {time_current - SyncHiveDb.time_start}s")
                log.info(f"[MASSIVE] Current system time: {datetime.now().isoformat(sep=' ', timespec='milliseconds')}")
                log.info(log_memory_usage())
                self.rate = minmax(self.rate, len(blocks), time_current - time_before_waiting_for_data, lbound)

                if block_end - block_start > 1.0 or is_debug:
                    otm = OPSM.log_current("Operations present in the processed blocks")
                    ftm = FSM.log_current("Flushing times")
                    wtm = WSM.log_current("Waiting times")
                    log.info(f"Calculated time: {otm + ftm + wtm:.4f} s.")

                OPSM.next_blocks()
                FSM.next_blocks()
                WSM.next_blocks()

                lbound = to
                PC.broadcast(BroadcastObject('sync_current_block', lbound, 'blocks'))

                num = num + 1
        except Exception:
            log.exception("Exception caught during processing blocks...")
            set_exception_thrown()
            raise

        return num

    def _get_active_db_connections(self):
        sql = "SELECT application_name FROM pg_stat_activity WHERE application_name LIKE 'hivemind_%';"
        active_connections = self._db.query_all(sql)
        return active_connections

    @staticmethod
    def _assert_connections_closed(connections_before: Iterable, connections_after: Iterable) -> None:
        assert_message = (
            f'Some db connections used in '
            f'{"LIVE" if DbLiveContextHolder.is_live_context() else "MASSIVE"} sync were not closed!\n'
            f'before: {connections_before}\n'
            f'after: {connections_after}'
        )

        assert set(connections_before) == set(connections_after), assert_message

    def _wait_for_connections_closed(self, connections_before: Iterable) -> None:
        active_connections = []
        for it in range(1, 11):
            active_connections = self._get_active_db_connections()
            if set(connections_before) == set(active_connections):
                return

            log.info(
                f'Some db connections used in '
                f'{"LIVE" if DbLiveContextHolder.is_live_context() else "MASSIVE"} sync were not closed!\n'
                f'before: {connections_before}\n'
                f'after: {active_connections}\n'
                f'try: {it}'
            )

            time.sleep(0.1)

        self._assert_connections_closed(connections_before, active_connections)

"""Hive sync manager."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import logging
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
from hive.indexer.hive_db.haf_functions import context_attach, context_detach
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.indexer.mocking.mock_block_provider import MockBlockProvider
from hive.indexer.mocking.mock_vops_provider import MockVopsProvider
from hive.server.common.payout_stats import PayoutStats
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

log = logging.getLogger(__name__)


class SyncHiveDb:
    def __init__(self, conf: Conf):
        self._conf = conf
        self._db = conf.db()

        # Might be lower or higher than actual block number stored in HAF database
        self._last_block_to_process = self._conf.get('test_max_block')

        self._last_block_for_massive_sync = self._conf.get('test_last_block_for_massive')

        self._massive_blocks_data_provider = None
        self._lbound = None
        self._ubound = None
        self._databases = None

    def __enter__(self):
        log.info("Entering HAF mode synchronization")
        set_custom_signal_handlers()

        Blocks.setup(conf=self._conf)

        Community.start_block = self._conf.get("community_start_block")
        DbState.initialize()

        self._show_info(self._db)

        self._check_log_explain_queries()

        context_attach(db=self._db, block_number=Blocks.head_num())

        self._load_mock_data()
        Accounts.load_ids()  # prefetch id->name and id->rank memory maps

        return self

    def __exit__(self, exc_type, value, traceback):
        log.info("Exiting HAF mode synchronization")
        Blocks.setup_own_db_access(shared_db_adapter=self._db)  # needed for PayoutStats.generate
        PayoutStats.generate(separate_transaction=True)

        last_imported_block = Blocks.head_num()
        log.info(f'LAST IMPORTED BLOCK IS: {last_imported_block}')
        context_attach(db=self._db, block_number=last_imported_block)

        Blocks.close_own_db_access()
        if self._databases:
            self._databases.close()

    def run(self) -> None:
        start_time = perf()
        is_in_live_sync = False

        log.info(f"Using HAF database as block data provider, pointed by url: '{self._conf.get('database_url')}'")

        while True:
            if not can_continue_thread():
                restore_default_signal_handlers()
                return

            active_connections_before = self._get_active_db_connections()

            last_imported_block = Blocks.head_num()
            log.info(f"Last imported block is: {last_imported_block}")

            self._db.query("START TRANSACTION")
            self._lbound, self._ubound = self._query_for_app_next_block()

            if self._last_block_to_process:
                if last_imported_block >= self._last_block_to_process:
                    log.info(f"REACHED test_max_block of {self._last_block_to_process}")
                    self._db.query("COMMIT")
                    return

                if not (self._lbound and self._ubound):  # all blocks from HAF db processed
                    self._lbound = last_imported_block + 1
                    self._ubound = self._last_block_to_process
                else:
                    self._ubound = min(self._last_block_to_process, self._ubound)

            allow_massive = True
            if self._last_block_for_massive_sync and self._lbound:
                if self._lbound < self._last_block_for_massive_sync:
                    self._ubound = self._last_block_for_massive_sync

                if self._lbound > self._last_block_for_massive_sync:
                    allow_massive = False

            if not (self._lbound and self._ubound):
                self._db.query("COMMIT")
                continue

            log.info(f"target_head_block: {self._ubound}")
            log.info(f"test_max_block: {self._last_block_to_process}")
            log.info(f"last_block_for_massive: {self._last_block_for_massive_sync}")

            if self._ubound - self._lbound > 100 and allow_massive:
                # mode with detached indexes and context
                log.info("[MASSIVE] *** MASSIVE blocks processing ***")
                self._db.query("COMMIT")  # in massive we re not operating in same transaction as app_next_block query

                DbLiveContextHolder.set_live_context(False)
                Blocks.setup_own_db_access(shared_db_adapter=self._db)
                self._massive_blocks_data_provider = MassiveBlocksDataProviderHiveDb(
                    conf=self._conf,
                    databases=MassiveBlocksDataProviderHiveDb.Databases(db_root=self._db),
                )

                self._massive_blocks_data_provider.update_sync_block_range(self._lbound, self._ubound)

                DbState.before_massive_sync(self._lbound, self._ubound)

                context_detach(db=self._db)
                log.info(f"[MASSIVE] Attempting to process block range: <{self._lbound}:{self._ubound}>")
                self._catchup_irreversible_block(is_massive_sync=True)

                if not can_continue_thread():
                    restore_default_signal_handlers()
                    return

                last_block = Blocks.head_num()
                DbState.finish_massive_sync(current_imported_block=last_block)
                if not self._massive_blocks_data_provider.were_mocks_after_db_blocks:
                    context_attach(db=self._db, block_number=last_block)
                Blocks.close_own_db_access()
                self._massive_blocks_data_provider.close_databases()

                active_connections_after_massive = self._get_active_db_connections()
                self._assert_connections_closed(active_connections_before, active_connections_after_massive)

            else:
                # mode with attached indexes and context
                log.info("[SINGLE] *** SINGLE block processing***")
                log.info(f"[SINGLE] Current system time: {datetime.now().isoformat(sep=' ', timespec='milliseconds')}")

                if not is_in_live_sync:
                    is_in_live_sync = True
                    log.info(
                        f"[SINGLE] Switched to single block processing mode after: {secs_to_str(perf() - start_time)}"
                    )

                DbLiveContextHolder.set_live_context(True)
                Blocks.setup_own_db_access(shared_db_adapter=self._db)
                self._massive_blocks_data_provider = MassiveBlocksDataProviderHiveDb(
                    conf=self._conf,
                    databases=MassiveBlocksDataProviderHiveDb.Databases(db_root=self._db, shared=True),
                )

                self._massive_blocks_data_provider.update_sync_block_range(self._lbound, self._lbound)

                if not Blocks.is_consistency():
                    last_block = Blocks.head_num()
                    DbState._after_massive_sync(current_imported_block=last_block)
                assert Blocks.is_consistency()

                log.info(f"[SINGLE] Attempting to process first block in range: <{self._lbound}:{self._ubound}>")
                self._massive_blocks_data_provider.start_without_threading()
                blocks = self._massive_blocks_data_provider.get(number_of_blocks=1)
                Blocks.process_multi(blocks, is_massive_sync=False)

                active_connections_after_live = self._get_active_db_connections()
                self._assert_connections_closed(active_connections_before, active_connections_after_live)

    def _query_for_app_next_block(self) -> Tuple[int, int]:
        log.info("Querying for next block for app context...")
        lbound, ubound = self._db.query_row(f"SELECT * FROM hive.app_next_block('{SCHEMA_NAME}')")
        log.info(f"Next block range from hive.app_next_block is: <{lbound}:{ubound}>")
        return lbound, ubound

    def _catchup_irreversible_block(self, is_massive_sync: bool = False) -> None:
        assert self._massive_blocks_data_provider is not None

        self._process_blocks_from_provider(
            massive_block_provider=self._massive_blocks_data_provider,
            is_massive_sync=is_massive_sync,
            lbound=self._lbound,
            ubound=self._ubound,
        )
        log.info(
            f"Block range: <{self._lbound}:{self._ubound}> processing"
            f" {'finished' if can_continue_thread() else 'interrupted'}"
        )

    def _check_log_explain_queries(self) -> None:
        if self._conf.get("log_explain_queries"):
            is_superuser = self._db.query_one("SELECT is_superuser()")
            assert (
                is_superuser
            ), 'The parameter --log_explain_queries=true can be used only when connect to the database with SUPERUSER privileges'

    def _load_mock_data(self) -> None:
        paths = self._conf.get("mock_block_data_path") or []
        for path in paths:
            MockBlockProvider.load_block_data(path)

        if mock_vops_data_path := self._conf.get("mock_vops_data_path"):
            MockVopsProvider.load_block_data(mock_vops_data_path)

    @staticmethod
    def _show_info(database: Db) -> None:
        last_block = Blocks.head_num()

        sql = f"SELECT level, patch_date, patched_to_revision FROM {SCHEMA_NAME}.hive_db_patch_level ORDER BY level DESC LIMIT 1"
        patch_level_data = database.query_row(sql)

        from hive.utils.misc import show_app_version

        show_app_version(log, last_block, patch_level_data)

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

    @staticmethod
    def _block_consumer(
        blocks_data_provider: BlocksProviderBase, is_massive_sync: bool, lbound: int, ubound: int
    ) -> int:
        from hive.utils.stats import minmax

        is_debug = log.isEnabledFor(10)
        num = 0
        time_start = OPSM.start()
        rate = {}
        LIMIT_FOR_PROCESSED_BLOCKS = 1000

        rate = minmax(rate, 0, 1.0, 0)

        def print_summary():
            stop = OPSM.stop(time_start)
            log.info("=== TOTAL STATS ===")
            wtm = WSM.log_global("Total waiting times")
            ftm = FSM.log_global("Total flush times")
            otm = OPSM.log_global("All operations present in the processed blocks")
            ttm = ftm + otm + wtm
            log.info("Elapsed time: %.4fs. Calculated elapsed time: %.4fs. Difference: %.4fs", stop, ttm, stop - ttm)
            if rate:
                log.info(
                    "Highest block processing rate: %.4f bps. %d:%d", rate['max'], rate['max_from'], rate['max_to']
                )
                log.info("Lowest block processing rate: %.4f bps. %d:%d", rate['min'], rate['min_from'], rate['min_to'])
            log.info("=== TOTAL STATS ===")

        try:
            Blocks.set_end_of_sync_lib(ubound)
            count = ubound - lbound + 1
            timer = Timer(count, entity='block', laps=['rps', 'wps'])

            while lbound <= ubound:
                number_of_blocks_to_proceed = min([LIMIT_FOR_PROCESSED_BLOCKS, ubound - lbound + 1])
                time_before_waiting_for_data = perf()

                blocks = blocks_data_provider.get(number_of_blocks_to_proceed)

                if not can_continue_thread():
                    break

                assert len(blocks) == number_of_blocks_to_proceed

                to = min(lbound + number_of_blocks_to_proceed, ubound + 1)
                timer.batch_start()

                block_start = perf()
                Blocks.process_multi(blocks, is_massive_sync)
                block_end = perf()

                timer.batch_lap()
                timer.batch_finish(len(blocks))
                time_current = perf()

                prefix = (
                    "[MASSIVE]"
                    f" Got block {min(lbound + number_of_blocks_to_proceed - 1, ubound)} @ {blocks[-1].get_date()}"
                )

                log.info(timer.batch_status(prefix))
                log.info(f"[MASSIVE] Time elapsed: {time_current - time_start}s")
                log.info(f"[MASSIVE] Current system time: {datetime.now().isoformat(sep=' ', timespec='milliseconds')}")
                log.info(log_memory_usage())
                rate = minmax(rate, len(blocks), time_current - time_before_waiting_for_data, lbound)

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

                if not can_continue_thread():
                    break
        except Exception:
            log.exception("Exception caught during processing blocks...")
            set_exception_thrown()
            print_summary()
            raise

        print_summary()
        return num

    @classmethod
    def _process_blocks_from_provider(
        cls, massive_block_provider: BlocksProviderBase, is_massive_sync: bool, lbound: int, ubound: int
    ) -> None:
        with ThreadPoolExecutor(max_workers=2) as pool:
            block_data_provider_future = pool.submit(cls._blocks_data_provider, massive_block_provider)
            block_consumer_future = pool.submit(
                cls._block_consumer, massive_block_provider, is_massive_sync, lbound, ubound
            )

            consumer_exception = block_consumer_future.exception()
            block_data_provider_exception = block_data_provider_future.exception()

            if consumer_exception:
                raise consumer_exception

            if block_data_provider_exception:
                raise block_data_provider_exception

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

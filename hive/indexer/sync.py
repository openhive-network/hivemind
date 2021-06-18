"""Hive sync manager."""

import logging
from time import perf_counter as perf
import ujson as json

import queue
from concurrent.futures import ThreadPoolExecutor

from hive.db.db_state import DbState

from hive.utils.timer import Timer
from hive.steem.block.stream import MicroForkException
from hive.indexer.hive_rpc.massive_blocks_data_provider_hive_rpc import MassiveBlocksDataProviderHiveRpc
from hive.steem.block.stream import BlockStream
from hive.steem.signal import finish_signals_handler, set_exception_thrown, can_continue_thread

from hive.indexer.blocks import Blocks
from hive.indexer.accounts import Accounts
from hive.indexer.follow import Follow
from hive.indexer.community import Community
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.indexer.block import Block, BlocksProviderBase

from hive.server.common.payout_stats import PayoutStats
from hive.server.common.mentions import Mentions

from hive.server.common.mutes import Mutes

from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.stats import WaitingStatusManager as WSM
from hive.utils.stats import PrometheusClient as PC
from hive.utils.stats import BroadcastObject
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.misc import show_app_version, log_memory_usage

from hive.indexer.mock_block_provider import MockBlockProvider
from hive.indexer.mock_vops_provider import MockVopsProvider
from hive.indexer.db_adapter_holder import DbLiveContextHolder

from datetime import datetime

from signal import signal, SIGINT, SIGTERM, getsignal
from threading import Thread
from collections import deque


log = logging.getLogger(__name__)

CONTINUE_PROCESSING = True

EXCEPTION_THROWN = AtomicLong(0)
FINISH_SIGNAL_DURING_SYNC = AtomicLong(0)

old_sig_int_handler = None
old_sig_term_handler = None
trail_blocks = None

def set_handlers():
    global old_sig_int_handler
    global old_sig_term_handler
    old_sig_int_handler = signal(SIGINT, finish_signals_handler)
    old_sig_term_handler = signal(SIGTERM, finish_signals_handler)

def restore_handlers():
    signal(SIGINT, old_sig_int_handler)
    signal(SIGTERM, old_sig_term_handler)

def finish_signals_handler(signal, frame):
    global FINISH_SIGNAL_DURING_SYNC
    FINISH_SIGNAL_DURING_SYNC += 1
    log.info("""
                  **********************************************************
                  CAUGHT {}. PLEASE WAIT... PROCESSING DATA IN QUEUES...
                  **********************************************************
    """.format( "SIGINT" if signal == SIGINT else "SIGTERM" ) )

def show_info(self):
    database_head_block = Blocks.head_num()

    sql = "SELECT level, patch_date, patched_to_revision FROM hive_db_patch_level ORDER BY level DESC LIMIT 1"
    patch_level_data = self._db.query_row(sql)

    from hive.utils.misc import show_app_version;
    show_app_version(log, database_head_block, patch_level_data)

def set_exception_thrown():
    global EXCEPTION_THROWN
    EXCEPTION_THROWN += 1

def can_continue_thread():
    return EXCEPTION_THROWN.value == 0 and FINISH_SIGNAL_DURING_SYNC.value == 0

def _blocks_data_provider(blocks_data_provider):
    try:
        futures = blocks_data_provider.start()

        for future in futures:
            exception = future.exception()
            if exception:
                raise exception
    except:
        log.exception("Exception caught during fetching blocks data")
        raise

def _block_consumer(blocks_data_provider, is_initial_sync, lbound, ubound):
    from hive.utils.stats import minmax
    is_debug = log.isEnabledFor(10)
    num = 0
    time_start = OPSM.start()
    rate = {}
    LIMIT_FOR_PROCESSED_BLOCKS = 1000;

    rate = minmax(rate, 0, 1.0, 0)
    sync_type_prefix = "[INITIAL SYNC]" if is_initial_sync else "[FAST SYNC]"

    def print_summary():
        stop = OPSM.stop(time_start)
        log.info("=== TOTAL STATS ===")
        wtm = WSM.log_global("Total waiting times")
        ftm = FSM.log_global("Total flush times")
        otm = OPSM.log_global("All operations present in the processed blocks")
        ttm = ftm + otm + wtm
        log.info(f"Elapsed time: {stop :.4f}s. Calculated elapsed time: {ttm :.4f}s. Difference: {stop - ttm :.4f}s")
        if rate:
            log.info(f"Highest block processing rate: {rate['max'] :.4f} bps. From: {rate['max_from']} To: {rate['max_to']}")
            log.info(f"Lowest block processing rate: {rate['min'] :.4f} bps. From: {rate['min_from']} To: {rate['min_to']}")
        log.info("=== TOTAL STATS ===")

    try:
        Blocks.set_end_of_sync_lib( ubound )
        count = ubound - lbound
        timer = Timer(count, entity='block', laps=['rps', 'wps'])

        while lbound < ubound:
            number_of_blocks_to_proceed = min( [ LIMIT_FOR_PROCESSED_BLOCKS, ubound - lbound  ] )
            time_before_waiting_for_data = perf()

            blocks = blocks_data_provider.get( number_of_blocks_to_proceed )

            if not can_continue_thread():
                break;

            assert len(blocks) == number_of_blocks_to_proceed

            to = min(lbound + number_of_blocks_to_proceed, ubound)
            timer.batch_start()

            block_start = perf()
            Blocks.process_multi(blocks, is_initial_sync)
            block_end = perf()

            timer.batch_lap()
            timer.batch_finish(len(blocks))
            time_current = perf()

            prefix = ("%s Got block %d @ %s" % (
                sync_type_prefix, to - 1, blocks[-1].get_date()))
            log.info(timer.batch_status(prefix))
            log.info("%s Time elapsed: %fs", sync_type_prefix, time_current - time_start)
            log.info("%s Current system time: %s", sync_type_prefix, datetime.now().strftime("%H:%M:%S"))
            log.info(log_memory_usage())
            rate = minmax(rate, len(blocks), time_current - time_before_waiting_for_data, lbound)

            if block_end - block_start > 1.0 or is_debug:
                otm = OPSM.log_current("Operations present in the processed blocks")
                ftm = FSM.log_current("Flushing times")
                wtm = WSM.log_current("Waiting times")
                log.info(f"Calculated time: {otm+ftm+wtm :.4f} s.")

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

def _process_blocks_from_provider(self, massive_block_provider, is_initial_sync, lbound, ubound):
    assert issubclass( type(massive_block_provider), BlocksProviderBase )

    with ThreadPoolExecutor(max_workers = 2) as pool:
        block_data_provider_future = pool.submit(_blocks_data_provider, massive_block_provider)
        blockConsumerFuture = pool.submit(_block_consumer, massive_block_provider, is_initial_sync, lbound, ubound)

        consumer_exception = blockConsumerFuture.exception()
        block_data_provider_exception = block_data_provider_future.exception()

        if consumer_exception:
            raise consumer_exception

        if block_data_provider_exception:
            raise block_data_provider_exception

class DBSync:
    def __init__(self, mgr_sync, live_context):
        self._mgr_sync = mgr_sync
        DbLiveContextHolder.set_live_context(live_context)

    def __enter__(self):
        assert self._mgr_sync._db, "The database must exist"

        log.info("Entering into {} synchronization".format( "LIVE" if DbLiveContextHolder.is_live_context() else "MASSIVE" ))
        Blocks.setup_own_db_access(self._mgr_sync._db)
        log.info("Exiting from {} synchronization".format( "LIVE" if DbLiveContextHolder.is_live_context() else "MASSIVE" ))

        return self

    def __exit__(self, exc_type, value, traceback):
        Blocks.close_own_db_access()

class MassiveSync(DBSync):
    def __init__(self, mgr_sync):
        super().__init__(mgr_sync, False)

    def run(self):
        old_sig_int_handler = getsignal(SIGINT)
        old_sig_term_handler = getsignal(SIGTERM)

        set_handlers()

        Community.start_block = self._mgr_sync._conf.get("community_start_block")

        # ensure db schema up to date, check app status
        DbState.initialize()
        if self._conf.get("log_explain_queries"):
            is_superuser = self._db.query_one( "SELECT is_superuser()" )
            assert is_superuser, 'The parameter --log_explain_queries=true can be used only when connect to the database with SUPERUSER privileges'

        show_info(self._mgr_sync)

        paths = self._mgr_sync._conf.get("mock_block_data_path") or []
        for path in paths:
          self._mgr_sync.load_mock_data(path)

        mock_vops_data_path = self._mgr_sync._conf.get("mock_vops_data_path")
        if mock_vops_data_path:
            MockVopsProvider.load_block_data(mock_vops_data_path)
            # MockVopsProvider.print_data()

        # prefetch id->name and id->rank memory maps
        Accounts.load_ids()

        # community stats
        update_communities_posts_and_rank(self._mgr_sync._db)

        last_imported_block = Blocks.head_num()
        hived_head_block = self._mgr_sync._conf.get('test_max_block') or self._mgr_sync._steem.last_irreversible()

        log.info("target_head_block : %s", hived_head_block)

        if DbState.is_initial_sync():
            DbState.before_initial_sync(last_imported_block, hived_head_block)
            # resume initial sync
            self._mgr_sync.initial()
            if not can_continue_thread():
                restore_handlers()
                return
            current_imported_block = Blocks.head_num()
            # beacuse we cannot break long sql operations, then we back default CTRL+C
            # behavior for the time of post initial actions
            restore_handlers()
            try:
                DbState.finish_initial_sync(current_imported_block)
            except KeyboardInterrupt:
                log.info("Break finish initial sync")
                set_exception_thrown()
                return
            set_handlers()
        else:
            # recover from fork
            Blocks.verify_head(self._mgr_sync._steem)

        self._mgr_sync._update_chain_state()

        global trail_blocks
        trail_blocks = self._mgr_sync._conf.get('trail_blocks')
        assert trail_blocks >= 0
        assert trail_blocks <= 100

class LiveSync(DBSync):
    def __init__(self, mgr_sync):
        super().__init__(mgr_sync, True)

    def run(self):
        import sys
        max_block_limit = sys.maxsize
        do_stale_block_check = True
        if self._mgr_sync._conf.get('test_max_block'):
            max_block_limit = self._mgr_sync._conf.get('test_max_block')
            do_stale_block_check = False
            # Correct max_block_limit by trail_blocks
            max_block_limit = max_block_limit - trail_blocks
            log.info("max_block_limit corrected by specified trail_blocks number: %d is: %d", trail_blocks, max_block_limit)

        if self._mgr_sync._conf.get('test_disable_sync'):
            # debug mode: no sync, just stream
            result =  self._mgr_sync.listen(trail_blocks, max_block_limit, do_stale_block_check)
            restore_handlers()
            return result

        while True:
            # sync up to irreversible block
            self._mgr_sync.from_steemd()
            if not can_continue_thread():
                break

            head = Blocks.head_num()
            if head >= max_block_limit:
                self._mgr_sync.refresh_sparse_stats()
                log.info("Exiting [LIVE SYNC] because irreversible block sync reached specified block limit: %d", max_block_limit)
                break;

            try:
                # listen for new blocks
                self._mgr_sync.listen(trail_blocks, max_block_limit, do_stale_block_check)
            except MicroForkException as e:
                # attempt to recover by restarting stream
                log.error("microfork: %s", repr(e))

            head = Blocks.head_num()
            if head >= max_block_limit:
                self._mgr_sync.refresh_sparse_stats()
                log.info("Exiting [LIVE SYNC] because of specified block limit: %d", max_block_limit)
                break;

            if not can_continue_thread():
                break
        restore_handlers()

class Sync:
    """Manages the sync/index process.

    Responsible for initial sync, fast sync, and listen (block-follow).
    """

    def __init__(self, conf):
        self._conf = conf
        self._db = conf.db()

        log.info("Using hived url: `%s'", self._conf.get('steemd_url'))

        self._steem = conf.steem()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, value, traceback): pass

    def load_mock_data(self,mock_block_data_path):
        if mock_block_data_path:
            MockBlockProvider.load_block_data(mock_block_data_path)
            # MockBlockProvider.print_data()

    def refresh_sparse_stats(self):
        # normally it should be refreshed in various time windows
        # but we need the ability to do it all at the same time
        self._update_chain_state()
        update_communities_posts_and_rank(self._db)
        with ThreadPoolExecutor(max_workers=2) as executor:
            executor.submit(PayoutStats.generate)
            executor.submit(Mentions.refresh)

    def run(self):
        """Initialize state; setup/recovery checks; sync and runloop."""
        with MassiveSync(mgr_sync=self) as massive_sync:
          massive_sync.run()

        with LiveSync(mgr_sync=self) as live_sync:
          live_sync.run()

    def initial(self):
        """Initial sync routine."""
        assert DbState.is_initial_sync(), "already synced"

        log.info("[INIT] *** Initial fast sync ***")
        self.from_steemd(is_initial_sync=True)
        if not can_continue_thread():
            return

    def from_steemd(self, is_initial_sync=False, chunk_size=1000):
        """Fast sync strategy: read/process blocks in batches."""
        steemd = self._steem

        lbound = Blocks.head_num() + 1
        ubound = steemd.last_irreversible()

        if self._conf.get('test_max_block') and self._conf.get('test_max_block') < ubound:
            ubound = self._conf.get('test_max_block')

        count = ubound - lbound
        if count < 1:
            return

        massive_blocks_data_provider = None
        databases = None
        if self._conf.get('hived_database_url'):
            databases = MassiveBlocksDataProviderHiveDb.Databases( self._conf )
            massive_blocks_data_provider = MassiveBlocksDataProviderHiveDb(
                  databases
                , self._conf.get( 'max_batch' )
                , lbound
                , ubound
                , can_continue_thread
                , set_exception_thrown
            )
        else:
            massive_blocks_data_provider = MassiveBlocksDataProviderHiveRpc(
                  self._conf
                , self._steem
                , self._conf.get( 'max_workers' )
                , self._conf.get( 'max_workers' )
                , self._conf.get( 'max_batch' )
                , lbound
                , ubound
                , can_continue_thread
                , set_exception_thrown
            )
        _process_blocks_from_provider( self, massive_blocks_data_provider, is_initial_sync, lbound, ubound )

        if databases:
            databases.close()

    def _stream_blocks(self, start_from, breaker, exception_reporter, trail_blocks=0, max_gap=100, do_stale_block_check=True):
        """Stream blocks. Returns a generator."""
        return BlockStream.stream(self._conf, self._steem, start_from, breaker, exception_reporter, trail_blocks, max_gap, do_stale_block_check)

    def listen(self, trail_blocks, max_sync_block, do_stale_block_check):
        """Live (block following) mode.
            trail_blocks - how many blocks need to be collected to start processed the oldest ( delay in blocks processing against blocks collecting )
            max_sync_block - limit of blocks to sync, the function will return if it is reached
            do_stale_block_check - check if the last collected block is not older than 60s
        """

        # debug: no max gap if disable_sync in effect
        max_gap = None if self._conf.get('test_disable_sync') else 100

        steemd = self._steem
        hive_head = Blocks.head_num()

        log.info("[LIVE SYNC] Entering listen with HM head: %d", hive_head)

        if hive_head >= max_sync_block:
            self.refresh_sparse_stats()
            log.info("[LIVE SYNC] Exiting due to block limit exceeded: synced block number: %d, max_sync_block: %d", hive_head, max_sync_block)
            return

        for block in self._stream_blocks(hive_head + 1, can_continue_thread, set_exception_thrown, trail_blocks, max_gap, do_stale_block_check):
            if not can_continue_thread():
                break;
            num = block.get_num()
            log.info("[LIVE SYNC] =====> About to process block %d with timestamp %s", num, block.get_date())

            start_time = perf()

            Blocks.process_multi([block], False)
            otm = OPSM.log_current("Operations present in the processed blocks")
            ftm = FSM.log_current("Flushing times")

            ms = (perf() - start_time) * 1000
            log.info("[LIVE SYNC] <===== Processed block %d at %s --% 4d txs"
                     " --% 5dms%s", num, block.get_date(), block.get_number_of_transactions(),
                     ms, ' SLOW' if ms > 1000 else '')
            log.info("[LIVE SYNC] Current system time: %s", datetime.now().strftime("%H:%M:%S"))

            if num % 1200 == 0: #1hour
                log.warning("head block %d @ %s", num, block.get_date())
                log.info("[LIVE SYNC] hourly stats")

                log.info("[LIVE SYNC] filling payout_stats_view executed")
                with ThreadPoolExecutor(max_workers=2) as executor:
                    executor.submit(PayoutStats.generate)
                    executor.submit(Mentions.refresh)
            if num % 200 == 0: #10min
                update_communities_posts_and_rank(self._db)
            if num % 20 == 0: #1min
                self._update_chain_state()

            PC.broadcast(BroadcastObject('sync_current_block', num, 'blocks'))
            FSM.next_blocks()
            OPSM.next_blocks()

            if num >= max_sync_block:
                log.info("Stopping [LIVE SYNC] because of specified block limit: %d", max_sync_block)
                break

    # refetch dynamic_global_properties, feed price, etc
    def _update_chain_state(self):
        """Update basic state props (head block, feed price) in db."""
        state = self._steem.gdgp_extended()
        self._db.query("""UPDATE hive_state SET block_num = :block_num,
                       steem_per_mvest = :spm, usd_per_steem = :ups,
                       sbd_per_steem = :sps, dgpo = :dgpo""",
                       block_num=Blocks.head_num(),
                       spm=state['steem_per_mvest'],
                       ups=state['usd_per_steem'],
                       sps=state['sbd_per_steem'],
                       dgpo=json.dumps(state['dgpo']))
        return state['dgpo']['head_block_number']

"""Hive sync manager."""

import logging
from time import perf_counter as perf
import ujson as json

import queue
from concurrent.futures import ThreadPoolExecutor

from hive.db.db_state import DbState

from hive.utils.timer import Timer
from hive.steem.block.stream import MicroForkException

from hive.indexer.blocks import Blocks
from hive.indexer.accounts import Accounts
from hive.indexer.follow import Follow

from hive.server.common.payout_stats import PayoutStats
from hive.server.common.mentions import Mentions

from hive.server.common.mutes import Mutes

from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.stats import WaitingStatusManager as WSM
from hive.utils.stats import PrometheusClient as PC
from hive.utils.stats import BroadcastObject
from hive.utils.communities_rank import update_communities_posts_and_rank

from datetime import datetime

log = logging.getLogger(__name__)

CONTINUE_PROCESSING = True

def prepare_vops(vops_by_block):
    preparedVops = {}

    for blockNum, blockDict in vops_by_block.items():
        vopsList = blockDict['ops']
        preparedVops[blockNum] = vopsList

    return preparedVops

def _block_provider(node, queue, lbound, ubound, chunk_size):
    try:
        num = 0
        count = ubound - lbound
        log.info("[SYNC] start block %d, +%d to sync", lbound, count)
        timer = Timer(count, entity='block', laps=['rps', 'wps'])
        while CONTINUE_PROCESSING and lbound < ubound:
            to = min(lbound + chunk_size, ubound)
            timer.batch_start()
            blocks = node.get_blocks_range(lbound, to)
            lbound = to
            timer.batch_lap()
            queue.put(blocks)
            num = num + 1
        return num
    except KeyboardInterrupt:
        log.info("Caught SIGINT")

    except Exception:
        log.exception("Exception caught during fetching blocks")

def _vops_provider(conf, node, queue, lbound, ubound, chunk_size):
    try:
        num = 0
        count = ubound - lbound
        log.info("[SYNC] start vops %d, +%d to sync", lbound, count)
        timer = Timer(count, entity='vops-chunk', laps=['rps', 'wps'])

        while CONTINUE_PROCESSING and lbound < ubound:
            to = min(lbound + chunk_size, ubound)
            timer.batch_start()
            vops = node.enum_virtual_ops(conf, lbound, to)
            preparedVops = prepare_vops(vops)
            lbound = to
            timer.batch_lap()
            queue.put(preparedVops)
            num = num + 1
        return num
    except KeyboardInterrupt:
        log.info("Caught SIGINT")

    except Exception:
        log.exception("Exception caught during fetching vops...")

def _block_consumer(node, blocksQueue, vopsQueue, is_initial_sync, lbound, ubound, chunk_size):
    from hive.utils.stats import minmax
    is_debug = log.isEnabledFor(10)
    num = 0
    time_start = OPSM.start()
    rate = {}
    try:
        count = ubound - lbound
        timer = Timer(count, entity='block', laps=['rps', 'wps'])

        while lbound < ubound:

            wait_time_1 = WSM.start()
            if blocksQueue.empty() and CONTINUE_PROCESSING:
                log.info("Awaiting any block to process...")

            blocks = []
            if not blocksQueue.empty() or CONTINUE_PROCESSING:
                blocks = blocksQueue.get()
                blocksQueue.task_done()
            WSM.wait_stat('block_consumer_block', WSM.stop(wait_time_1))

            wait_time_2 = WSM.start()
            if vopsQueue.empty() and CONTINUE_PROCESSING:
                log.info("Awaiting any vops to process...")

            preparedVops = []
            if not vopsQueue.empty() or CONTINUE_PROCESSING:
                preparedVops = vopsQueue.get()
                vopsQueue.task_done()
            WSM.wait_stat('block_consumer_vop', WSM.stop(wait_time_2))

            to = min(lbound + chunk_size, ubound)

            timer.batch_start()

            block_start = perf()
            Blocks.process_multi(blocks, preparedVops, is_initial_sync)
            block_end = perf()

            timer.batch_lap()
            timer.batch_finish(len(blocks))
            time_current = perf()

            prefix = ("[INITIAL SYNC] Got block %d @ %s" % (
                to - 1, blocks[-1]['timestamp']))
            log.info(timer.batch_status(prefix))
            log.info("[INITIAL SYNC] Time elapsed: %fs", time_current - time_start)
            log.info("[INITIAL SYNC] Current system time: %s", datetime.now().strftime("%H:%M:%S"))
            rate = minmax(rate, len(blocks), time_current - wait_time_1, lbound)

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

            if not CONTINUE_PROCESSING and blocksQueue.empty() and vopsQueue.empty():
                break
    except KeyboardInterrupt:
        log.info("Caught SIGINT")
    except Exception:
        log.exception("Exception caught during processing blocks...")
    finally:
        stop = OPSM.stop(time_start)
        log.info("=== TOTAL STATS ===")
        wtm = WSM.log_global("Total waiting times")
        ftm = FSM.log_global("Total flush times")
        otm = OPSM.log_global("All operations present in the processed blocks")
        ttm = ftm + otm + wtm
        log.info(f"Elapsed time: {stop :.4f}s. Calculated elapsed time: {ttm :.4f}s. Difference: {stop - ttm :.4f}s")
        log.info(f"Highest block processing rate: {rate['max'] :.4f} bps. From: {rate['max_from']} To: {rate['max_to']}")
        log.info(f"Lowest block processing rate: {rate['min'] :.4f} bps. From: {rate['min_from']} To: {rate['min_to']}")
        log.info("=== TOTAL STATS ===")
        return num

def _node_data_provider(self, is_initial_sync, lbound, ubound, chunk_size):
    blocksQueue = queue.Queue(maxsize=10)
    vopsQueue = queue.Queue(maxsize=10)
    global CONTINUE_PROCESSING

    with ThreadPoolExecutor(max_workers = 4) as pool:
        try:
            pool.submit(_block_provider, self._steem, blocksQueue, lbound, ubound, chunk_size)
            pool.submit(_vops_provider, self._conf, self._steem, vopsQueue, lbound, ubound, chunk_size)
            blockConsumerFuture = pool.submit(_block_consumer, self._steem, blocksQueue, vopsQueue, is_initial_sync, lbound, ubound, chunk_size)

            blockConsumerFuture.result()
            if not CONTINUE_PROCESSING and blocksQueue.empty() and vopsQueue.empty():
                pool.shutdown(False)
        except KeyboardInterrupt:
            log.info(""" **********************************************************
                          CAUGHT SIGINT. PLEASE WAIT... PROCESSING DATA IN QUEUES...
                          **********************************************************
            """)
            CONTINUE_PROCESSING = False
    blocksQueue.join()
    vopsQueue.join()

class Sync:
    """Manages the sync/index process.

    Responsible for initial sync, fast sync, and listen (block-follow).
    """

    def __init__(self, conf):
        self._conf = conf
        self._db = conf.db()

        log.info("Using hived url: `%s'", self._conf.get('steemd_url'))

        self._steem = conf.steem()

    def run(self):
        """Initialize state; setup/recovery checks; sync and runloop."""
        from hive.version import VERSION, GIT_REVISION
        log.info("hivemind_version : %s", VERSION)
        log.info("hivemind_git_rev : %s", GIT_REVISION)

        from hive.db.schema import DB_VERSION as SCHEMA_DB_VERSION
        log.info("database_schema_version : %s", SCHEMA_DB_VERSION)

        # ensure db schema up to date, check app status
        DbState.initialize()
        Blocks.setup_own_db_access(self._db)

        # prefetch id->name and id->rank memory maps
        Accounts.load_ids()

        # load irredeemables
        mutes = Mutes(
            self._conf.get('muted_accounts_url'),
            self._conf.get('blacklist_api_url'))
        Mutes.set_shared_instance(mutes)

        # community stats
        update_communities_posts_and_rank()

        last_imported_block = Blocks.head_num()
        hived_head_block = self._conf.get('test_max_block') or self._steem.last_irreversible()

        log.info("database_head_block : %s", last_imported_block)
        log.info("target_head_block : %s", hived_head_block)

        if DbState.is_initial_sync():
            DbState.before_initial_sync(last_imported_block, hived_head_block)
            # resume initial sync
            self.initial()
            if not CONTINUE_PROCESSING:
                return
            current_imported_block = Blocks.head_num()
            DbState.finish_initial_sync(current_imported_block)
        else:
            # recover from fork
            Blocks.verify_head(self._steem)

        self._update_chain_state()

        if self._conf.get('test_max_block'):
            # debug mode: partial sync
            return self.from_steemd()
        if self._conf.get("exit_after_sync"):
            log.info("Exiting after sync on user request...")
            return
        if self._conf.get('test_disable_sync'):
            # debug mode: no sync, just stream
            return self.listen()

        while True:
            # sync up to irreversible block
            self.from_steemd()

            try:
                # listen for new blocks
                self.listen()
            except MicroForkException as e:
                # attempt to recover by restarting stream
                log.error("microfork: %s", repr(e))

    def initial(self):
        """Initial sync routine."""
        assert DbState.is_initial_sync(), "already synced"

        log.info("[INIT] *** Initial fast sync ***")
        self.from_steemd(is_initial_sync=True)
        if not CONTINUE_PROCESSING:
            return

        log.info("[INIT] *** Initial cache build ***")
        Follow.force_recount()

    def from_steemd(self, is_initial_sync=False, chunk_size=1000):
        """Fast sync strategy: read/process blocks in batches."""
        steemd = self._steem

        lbound = Blocks.head_num() + 1
        ubound = self._conf.get('test_max_block') or steemd.last_irreversible()

        count = ubound - lbound
        if count < 1:
            return

        if is_initial_sync:
            _node_data_provider(self, is_initial_sync, lbound, ubound, chunk_size)
            return

        log.info("[FAST SYNC] start block %d, +%d to sync", lbound, count)
        timer = Timer(count, entity='block', laps=['rps', 'wps'])
        while lbound < ubound:
            timer.batch_start()

            # fetch blocks
            to = min(lbound + chunk_size, ubound)
            blocks = steemd.get_blocks_range(lbound, to)
            vops = steemd.enum_virtual_ops(self._conf, lbound, to)
            prepared_vops = prepare_vops(vops)
            lbound = to
            timer.batch_lap()

            # process blocks
            Blocks.process_multi(blocks, prepared_vops, is_initial_sync)
            timer.batch_finish(len(blocks))

            otm = OPSM.log_current("Operations present in the processed blocks")
            ftm = FSM.log_current("Flushing times")

            _prefix = ("[FAST SYNC] Got block %d @ %s" % (
                to - 1, blocks[-1]['timestamp']))
            log.info(timer.batch_status(_prefix))

            OPSM.next_blocks()
            FSM.next_blocks()

            PC.broadcast(BroadcastObject('sync_current_block', to, 'blocks'))

    def listen(self):
        """Live (block following) mode."""
        trail_blocks = self._conf.get('trail_blocks')
        assert trail_blocks >= 0
        assert trail_blocks <= 100

        # debug: no max gap if disable_sync in effect
        max_gap = None if self._conf.get('test_disable_sync') else 100

        steemd = self._steem
        hive_head = Blocks.head_num()

        for block in steemd.stream_blocks(hive_head + 1, trail_blocks, max_gap):
            start_time = perf()

            num = int(block['block_id'][:8], base=16)
            log.info("[LIVE SYNC] =====> About to process block %d", num)
            vops = steemd.enum_virtual_ops(self._conf, num, num + 1)
            prepared_vops = prepare_vops(vops)

            Blocks.process_multi([block], prepared_vops, False)
            otm = OPSM.log_current("Operations present in the processed blocks")
            ftm = FSM.log_current("Flushing times")

            ms = (perf() - start_time) * 1000
            log.info("[LIVE SYNC] <===== Processed block %d at %s --% 4d txs"
                     " --% 5dms%s", num, block['timestamp'], len(block['transactions']),
                     ms, ' SLOW' if ms > 1000 else '')
            log.info("[LIVE SYNC] Current system time: %s", datetime.now().strftime("%H:%M:%S"))

            if num % 1200 == 0: #1hr
                log.warning("head block %d @ %s", num, block['timestamp'])
                log.info("[LIVE SYNC] hourly stats")

            if num % 1200 == 0: #1hour
                log.info("[LIVE SYNC] filling payout_stats_view executed")
                with ThreadPoolExecutor(max_workers=2) as executor:
                    executor.submit(PayoutStats.generate)
                    executor.submit(Mentions.refresh)
            if num % 200 == 0: #10min
                update_communities_posts_and_rank()
            if num % 20 == 0: #1min
                self._update_chain_state()

            PC.broadcast(BroadcastObject('sync_current_block', num, 'blocks'))
            FSM.next_blocks()
            OPSM.next_blocks()

    # refetch dynamic_global_properties, feed price, etc
    def _update_chain_state(self):
        """Update basic state props (head block, feed price) in db."""
        state = self._steem.gdgp_extended()
        self._db.query("""UPDATE hive_state SET block_num = :block_num,
                       steem_per_mvest = :spm, usd_per_steem = :ups,
                       sbd_per_steem = :sps, dgpo = :dgpo""",
                       block_num=state['dgpo']['head_block_number'],
                       spm=state['steem_per_mvest'],
                       ups=state['usd_per_steem'],
                       sps=state['sbd_per_steem'],
                       dgpo=json.dumps(state['dgpo']))
        return state['dgpo']['head_block_number']

"""Hive sync manager."""

import logging
import glob
from time import perf_counter as perf
import os
import ujson as json
import time

import concurrent, threading, queue
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import Future

from funcy.seqs import drop
from toolz import partition_all

from hive.db.db_state import DbState

from hive.utils.timer import Timer
from hive.steem.block.stream import MicroForkException

from hive.indexer.blocks import Blocks
from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.follow import Follow
from hive.indexer.community import Community
from hive.server.common.mutes import Mutes

#from hive.indexer.jobs import audit_cache_missing, audit_cache_deleted

log = logging.getLogger(__name__)

CONTINUE_PROCESSING = True

def print_ops_stats(prefix, ops_stats):
    log.info("############################################################################")
    log.info(prefix)
    sorted_stats = sorted(ops_stats.items(), key=lambda kv: kv[1], reverse=True)
    for (k, v) in sorted_stats:
        log.info("`{}': {}".format(k, v))

    log.info("############################################################################")

def prepare_vops(vops_by_block):
    preparedVops = {}

    for blockNum, blockDict in vops_by_block.items():
        vopsList = blockDict['ops']
        date = blockDict['timestamp']
        preparedVops[blockNum] = Blocks.prepare_vops(vopsList, date)
  
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

def _vops_provider(node, queue, lbound, ubound, chunk_size):
    try:
        num = 0
        count = ubound - lbound
        log.info("[SYNC] start vops %d, +%d to sync", lbound, count)
        timer = Timer(count, entity='vops-chunk', laps=['rps', 'wps'])

        while CONTINUE_PROCESSING and lbound < ubound:
            to = min(lbound + chunk_size, ubound)
            timer.batch_start()
            vops = node.enum_virtual_ops(lbound, to)
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
    num = 0
    try:
        count = ubound - lbound
        timer = Timer(count, entity='block', laps=['rps', 'wps'])
        total_ops_stats = {}
        time_start = perf()
        while lbound < ubound:
            if blocksQueue.empty() and CONTINUE_PROCESSING:
                log.info("Awaiting any block to process...")
            
            blocks = []
            if not blocksQueue.empty() or CONTINUE_PROCESSING:
                blocks = blocksQueue.get()
                blocksQueue.task_done()

            if vopsQueue.empty() and CONTINUE_PROCESSING:
                log.info("Awaiting any vops to process...")
            
            preparedVops = []
            if not vopsQueue.empty() or CONTINUE_PROCESSING:
                preparedVops = vopsQueue.get()
                vopsQueue.task_done()

            to = min(lbound + chunk_size, ubound)

            timer.batch_start()
            
            block_start = perf()
            ops_stats = dict(Blocks.process_multi(blocks, preparedVops, node, is_initial_sync))
            Blocks.ops_stats.clear()
            block_end = perf()

            timer.batch_lap()
            timer.batch_finish(len(blocks))
            time_current = perf()

            prefix = ("[SYNC] Got block %d @ %s" % (
                to - 1, blocks[-1]['timestamp']))
            log.info(timer.batch_status(prefix))
            log.info("[SYNC] Time elapsed: %fs", time_current - time_start)

            total_ops_stats = Blocks.merge_ops_stats(total_ops_stats, ops_stats)

            if block_end - block_start > 1.0:
                print_ops_stats("Operations present in the processed blocks:", ops_stats)

            lbound = to

            num = num + 1

            if not CONTINUE_PROCESSING and blocksQueue.empty() and vopsQueue.empty():
                break

        print_ops_stats("All operations present in the processed blocks:", total_ops_stats)
        return num
    except KeyboardInterrupt:
        log.info("Caught SIGINT")

    except Exception:
        log.exception("Exception caught during processing blocks...")

def _node_data_provider(self, is_initial_sync, lbound, ubound, chunk_size):
    blocksQueue = queue.Queue(maxsize=10)
    vopsQueue = queue.Queue(maxsize=10)
    global CONTINUE_PROCESSING

    with ThreadPoolExecutor(max_workers = 4) as pool:
        try:
            pool.submit(_block_provider, self._steem, blocksQueue, lbound, ubound, chunk_size)
            pool.submit(_vops_provider, self._steem, vopsQueue, lbound, ubound, chunk_size)
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
        self._steem = conf.steem()

    def run(self):
        """Initialize state; setup/recovery checks; sync and runloop."""

        # ensure db schema up to date, check app status
        DbState.initialize()

        # prefetch id->name and id->rank memory maps
        Accounts.load_ids()
        Accounts.fetch_ranks()

        # load irredeemables
        mutes = Mutes(
            self._conf.get('muted_accounts_url'),
            self._conf.get('blacklist_api_url'))
        Mutes.set_shared_instance(mutes)

        # community stats
        Community.recalc_pending_payouts()

        if DbState.is_initial_sync():
            # resume initial sync
            self.initial()
            if not CONTINUE_PROCESSING:
                return
            DbState.finish_initial_sync()

        else:
            # recover from fork
            Blocks.verify_head(self._steem)

            # perform cleanup if process did not exit cleanly
            # CachedPost.recover_missing_posts(self._steem)

        #audit_cache_missing(self._db, self._steem)
        #audit_cache_deleted(self._db)

        self._update_chain_state()

        if self._conf.get('test_max_block'):
            # debug mode: partial sync
            return self.from_steemd()
        if self._conf.get('test_disable_sync'):
            # debug mode: no sync, just stream
            return self.listen()

        while True:
            # sync up to irreversible block
            self.from_steemd()

            # take care of payout backlog
            # CachedPost.dirty_paidouts(Blocks.head_date())
            # CachedPost.flush(self._steem, trx=True)

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
        self.from_checkpoints()
        self.from_steemd(is_initial_sync=True)
        if not CONTINUE_PROCESSING:
            return

        log.info("[INIT] *** Initial cache build ***")
        # CachedPost.recover_missing_posts(self._steem)
        FeedCache.rebuild()
        Follow.force_recount()

    def from_checkpoints(self, chunk_size=1000):
        """Initial sync strategy: read from blocks on disk.

        This methods scans for files matching ./checkpoints/*.json.lst
        and uses them for hive's initial sync. Each line must contain
        exactly one block in JSON format.
        """
        # pylint: disable=no-self-use

        last_block = Blocks.head_num()

        tuplize = lambda path: [int(path.split('/')[-1].split('.')[0]), path]
        basedir = os.path.dirname(os.path.realpath(__file__ + "/../.."))
        files = glob.glob(basedir + "/checkpoints/*.json.lst")
        tuples = sorted(map(tuplize, files), key=lambda f: f[0])
        vops = {}

        last_read = 0
        for (num, path) in tuples:
            if last_block < num:
                log.info("[SYNC] Load %s. Last block: %d", path, last_block)
                with open(path) as f:
                    # each line in file represents one block
                    # we can skip the blocks we already have
                    skip_lines = last_block - last_read
                    remaining = drop(skip_lines, f)
                    for lines in partition_all(chunk_size, remaining):
                        raise RuntimeError("Sync from checkpoint disabled")
                        Blocks.process_multi(map(json.loads, lines), True)
                last_block = num
            last_read = num

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

        log.info("[SYNC] start block %d, +%d to sync", lbound, count)
        timer = Timer(count, entity='block', laps=['rps', 'wps'])
        while lbound < ubound:
            timer.batch_start()

            # fetch blocks
            to = min(lbound + chunk_size, ubound)
            blocks = steemd.get_blocks_range(lbound, to)
            vops = steemd.enum_virtual_ops(lbound, to)
            preparedVops = prepare_vops(vops)
            lbound = to
            timer.batch_lap()

            # process blocks
            Blocks.process_multi(blocks, preparedVops, steemd, is_initial_sync)
            timer.batch_finish(len(blocks))

            _prefix = ("[SYNC] Got block %d @ %s" % (
                to - 1, blocks[-1]['timestamp']))
            log.info(timer.batch_status(_prefix))

        if not is_initial_sync:
            # This flush is low importance; accounts are swept regularly.
            Accounts.flush(steemd, trx=True)

            # If this flush fails, all that could potentially be lost here is
            # edits and pre-payout votes. If the post has not been paid out yet,
            # then the worst case is it will be synced upon payout. If the post
            # is already paid out, worst case is to lose an edit.
            #CachedPost.flush(steemd, trx=True)

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

            self._db.query("START TRANSACTION")
            num = Blocks.process(block, {}, steemd)
            follows = Follow.flush(trx=False)
            accts = Accounts.flush(steemd, trx=False, spread=8)
            self._db.query("COMMIT")

            ms = (perf() - start_time) * 1000
            log.info("[LIVE] Got block %d at %s --% 4d txs,% 3d accts,% 3d follows"
                     " --% 5dms%s", num, block['timestamp'], len(block['transactions']),
                     accts, follows, ms, ' SLOW' if ms > 1000 else '')

            if num % 1200 == 0: #1hr
                log.warning("head block %d @ %s", num, block['timestamp'])
                log.info("[LIVE] hourly stats")
                Accounts.fetch_ranks()
                #Community.recalc_pending_payouts()
            if num % 200 == 0: #10min
                Community.recalc_pending_payouts()
            if num % 100 == 0: #5min
                log.info("[LIVE] 5-min stats")
                Accounts.dirty_oldest(500)
            if num % 20 == 0: #1min
                self._update_chain_state()

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

from hive.indexer.block import BlocksProviderBase
from hive.indexer.hive_rpc.blocks_provider import BlocksProvider
from hive.indexer.hive_rpc.vops_provider import VopsProvider
from hive.utils.stats import WaitingStatusManager as WSM

from hive.indexer.hive_rpc.block_from_rest import BlockFromRpc

from concurrent.futures import ThreadPoolExecutor, as_completed

import logging
import queue

log = logging.getLogger(__name__)

class MassiveBlocksDataProviderHiveRpc(BlocksProviderBase):
    def __init__(
          self
        , conf
        , node_client
        , blocks_get_threads
        , vops_get_threads
        , number_of_blocks_data_in_one_batch
        , lbound
        , ubound
        , breaker
        , exception_reporter
        , external_thread_pool = None):
        """
            conf - configuration
            node_client - SteemClient
            blocks_get_threads - number of threads which get blocks from node
            vops_get_threads - number of threads which get virtual operations from node
            number_of_blocks_data_in_one_batch - number of blocks which will be asked for the node in one HTTP get
            lbound - first block to get
            ubound - last block to get
            breaker - callable, returns False when processing must be stopped
            exception_reporter - callable, invoke to report an undesire exception in a thread
            external_thread_pool - thread pool controlled outside the class
        """

        BlocksProviderBase.__init__(self, breaker, exception_reporter)

        thread_pool = None
        if external_thread_pool:
            assert type(external_thread_pool) == ThreadPoolExecutor
            thread_pool = external_thread_pool
        else:
            thread_pool = MassiveBlocksDataProviderHiveRpc.create_thread_pool( blocks_get_threads, vops_get_threads  )

        self.blocks_provider = BlocksProvider(
              node_client._client["get_block"] if "get_block" in node_client._client else node_client._client["default"]
            , blocks_get_threads
            , number_of_blocks_data_in_one_batch
            , lbound
            , ubound
            , breaker
            , exception_reporter
            , thread_pool
        )

        self.vops_provider = VopsProvider(
              conf
            , node_client
            , vops_get_threads
            , number_of_blocks_data_in_one_batch
            , lbound
            , ubound
            , breaker
            , exception_reporter
            , thread_pool
        )

        self.vops_queue = queue.Queue( maxsize=self._operations_queue_size )
        self.blocks_queue = queue.Queue( maxsize=self._blocks_data_queue_size )

    def create_thread_pool( threads_for_blocks, threads_for_vops ):
        """Creates initialzied thread pool with number of threads required by the provider.
        You can pass the thread pool to provider during its creation to controll its lifetime
        outside the provider"""

        return ThreadPoolExecutor(
            BlocksProvider.get_number_of_threads( threads_for_blocks )
            +  VopsProvider.get_number_of_threads( threads_for_vops )
            )


    def get( self, number_of_blocks ):
        """Returns blocks and vops data for next number_of_blocks"""
        vops_and_blocks = { 'vops': [], 'blocks': [] }

        log.info("vops_queue.qsize: {} blocks_queue.qsize: {}".format(self.vops_queue.qsize(), self.blocks_queue.qsize()))

        wait_vops_time = WSM.start()
        if self.vops_queue.qsize() < number_of_blocks and self._breaker():
                 log.info("Awaiting any vops to process...")

        if not self.vops_queue.empty() or self._breaker():
            vops = self._get_from_queue( self.vops_queue, number_of_blocks )

            if self._breaker():
                assert len( vops ) == number_of_blocks
                vops_and_blocks[ 'vops' ] = vops
        WSM.wait_stat('block_consumer_vop', WSM.stop(wait_vops_time))

        wait_blocks_time = WSM.start()
        if  ( self.blocks_queue.qsize() < number_of_blocks ) and self._breaker():
            log.info("Awaiting any block to process...")

        if not self.blocks_queue.empty() or self._breaker():
            vops_and_blocks[ 'blocks' ] = self._get_from_queue( self.blocks_queue, number_of_blocks )
        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        result = []
        for vop_nr in range( len(vops_and_blocks['blocks']) ):
            if vops_and_blocks[ 'blocks' ][ vop_nr ] is not None:
                result.append( BlockFromRpc( vops_and_blocks[ 'blocks' ][ vop_nr ], vops_and_blocks[ 'vops' ][ vop_nr ] ) )

        return result

    def start(self):
        futures = self.blocks_provider.start( self.blocks_queue )
        futures.extend( self.vops_provider.start( self.vops_queue ) )

        return futures

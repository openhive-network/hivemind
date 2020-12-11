from hive.steem.blocks_provider import BlocksProvider
from hive.steem.vops_provider import VopsProvider
from hive.utils.stats import WaitingStatusManager as WSM

import logging
import queue

log = logging.getLogger(__name__)

class MassiveBlocksDataProvider:
    def __init__(
          cls
        , conf
        , node_client
        , blocks_get_threads
        , vops_get_threads
        , number_of_blocks_data_in_one_batch
        , lbound
        , ubound
        , breaker):
        """
            conf - configuration
            node_client - SteemClient
            blocks_get_threads - number of threads which get blocks from node
            vops_get_threads - number of threads which get virtual operations from node
            number_of_blocks_data_in_one_batch - number of blocks which will be asked for the node in one HTTP get
            lbound - first block to get
            ubound - last block to get
            breaker - callable, returns False when processing must be stopped
        """
        cls.blocks_provider = BlocksProvider(
              node_client._client["get_block"] if "get_block" in node_client._client else node_client._client["default"]
            , blocks_get_threads
            , number_of_blocks_data_in_one_batch
            , lbound
            , ubound
            , breaker
        )

        cls.vops_provider = VopsProvider(
              conf
            , node_client
            , vops_get_threads
            , number_of_blocks_data_in_one_batch
            , lbound
            , ubound
            , breaker
        )

        cls.vops_queue = queue.Queue( maxsize=10000 )
        cls.blocks_queue = queue.Queue( maxsize=10000 )
        cls.breaker = breaker

    def _get_from_queue( cls, data_queue, number_of_elements ):
        ret = []
        for element in range( number_of_elements ):
            if not cls.breaker():
                break
            while cls.breaker():
                try:
                    ret.append( data_queue.get(True, 1) )
                    data_queue.task_done()
                except queue.Empty:
                    continue
                break
        return ret

    def get( cls, number_of_blocks ):
        """Returns blocks and vops data for next number_of_blocks"""
        result = { 'vops': [], 'blocks': [] }

        wait_vops_time = WSM.start()
        if cls.vops_queue.qsize() < number_of_blocks and cls.breaker():
                 log.info("Awaiting any vops to process...")

        if not cls.vops_queue.empty() or cls.breaker():
            vops = cls._get_from_queue( cls.vops_queue, number_of_blocks )

            if cls.breaker():
                assert len( vops ) == number_of_blocks
                result[ 'vops' ] = vops
        WSM.wait_stat('block_consumer_vop', WSM.stop(wait_vops_time))

        wait_blocks_time = WSM.start()
        if  ( cls.blocks_queue.qsize() < number_of_blocks ) and cls.breaker():
            log.info("Awaiting any block to process...")

        if not cls.blocks_queue.empty() or cls.breaker():
            result[ 'blocks' ] = cls._get_from_queue( cls.blocks_queue, number_of_blocks )
        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        return result

    def start(cls):
        futures = cls.vops_provider.start( cls.vops_queue )
        futures.extend( cls.blocks_provider.start( cls.blocks_queue ) )

        return futures


from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
import queue
from time import sleep
import math

from hive.indexer.mock_block_provider import MockBlockProvider

log = logging.getLogger(__name__)

class BlocksProvider:
    """Starts threads which request node for blocks, and collect responses to one queue"""

    def __init__(cls, http_client, number_of_threads, blocks_per_request, start_block, max_block, breaker):
        """
            http_client - object which will ask the node for blocks
            number_of_threads - how many threads will be used to ask for blocks
            start_block - block from which the processing starts
            max_block - last to get block's number
            breaker - callable object which returns true if processing must be continues
        """

        assert number_of_threads > 0
        assert max_block > start_block
        assert breaker
        assert http_client
        assert blocks_per_request >= 1

        cls._responses_queues = []
        cls._breaker = breaker
        cls._start_block = start_block
        cls._max_block = max_block # to inlude upperbound in results
        cls._http_client = http_client
        cls._thread_pool = ThreadPoolExecutor(number_of_threads + 1 ) #+1 for a collecting thread
        cls._number_of_threads = number_of_threads
        cls._blocks_per_request = blocks_per_request

        # prepare quques and threads
        for i in range( 0, number_of_threads):
                cls._responses_queues.append( queue.Queue( maxsize = 50 ) )


    def thread_body_get_block( cls, blocks_shift ):
        for block in range ( cls._start_block + blocks_shift * cls._blocks_per_request, cls._max_block, cls._number_of_threads * cls._blocks_per_request ):
            if not cls._breaker():
                return;

            results = []
            if cls._blocks_per_request > 1:
                query_param = [{'block_num': i} for i in range( block, min( [ block + cls._blocks_per_request, cls._max_block ] ))]
                results = cls._http_client.exec( 'get_block', query_param, True )
            else:
                query_param = {'block_num': block}
                results.append(cls._http_client.exec( 'get_block', query_param, False ))

            if results:
                while cls._breaker():
                    try:
                        cls._responses_queues[ blocks_shift ].put( results, True, 1 )
                        break
                    except queue.Full:
                        continue

    def thread_body_blocks_collector( cls, queue_for_blocks ):
        currently_received_block =  cls._start_block - 1;
        while cls._breaker():
            # take in order all blocks from threads queues
            for blocks_queue in range ( 0, cls._number_of_threads ):
                if not cls._breaker():
                    return;
                while cls._breaker():
                    try:
                        blocks = cls._responses_queues[ blocks_queue ].get( True, 1)
                        cls._responses_queues[ blocks_queue ].task_done()
                        #split blocks range
                        for block in blocks:
                            block_mock = MockBlockProvider.get_block_data(currently_received_block+1, True)
                            if block_mock is not None:
                                if 'block' in block:
                                    block["block"]["transactions"].extend( block_mock["transactions"] )
                                    block["block"]["transaction_ids"].extend( block_mock["transaction_ids"] )
                                else:
                                    block["block"] = block_mock
                            if not 'block' in 'block': # if block not exists in the node nor moc
                                continue;

                            while cls._breaker():
                                try:
                                    queue_for_blocks.put( block['block'], True, 1 )
                                    currently_received_block += 1
                                    if currently_received_block >= (cls._max_block - 1):
                                        return
                                    break
                                except queue.Full:
                                    continue
                        break
                    except queue.Empty:
                        continue

    def start(cls, queue_for_blocks):
        futures = []
        for future_number in range(0, cls._number_of_threads):
            future = cls._thread_pool.submit( cls.thread_body_get_block, future_number  )
            futures.append( future )

        future = cls._thread_pool.submit( cls.thread_body_blocks_collector, queue_for_blocks )
        futures.append( future )
        return futures

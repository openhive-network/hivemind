
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
import queue
import math
from time import sleep

from hive.indexer.mock_block_provider import MockBlockProvider

log = logging.getLogger(__name__)

class VopsProvider:
    """Starts threads which request node for blocks, and collect responses to one queue"""

    def __init__(cls, conf, client, number_of_threads, blocks_per_request, start_block, max_block, breaker, exception_reporter, external_thread_pool = None):
        """
            conf - configuration
            steem client - object which will ask the node for blocks
            number_of_threads - how many threads will be used to ask for blocks
            start_block - block from which the processing starts
            max_block - last to get block's number
            breaker - callable object which returns true if processing must be continues
            exception_reporter - callable, invoke to report an undesire exception in a thread
            external_thread_pool - thread pool controlled outside the class
        """

        assert conf
        assert number_of_threads > 0
        assert max_block > start_block
        assert breaker
        assert exception_reporter
        assert client
        assert blocks_per_request >= 1

        cls._conf = conf
        cls._responses_queues = []
        cls._breaker = breaker
        cls._exception_reporter = exception_reporter
        cls._start_block = start_block
        cls._max_block = max_block # to inlude upperbound in results
        cls._client = client
        if external_thread_pool:
                assert type(external_thread_pool) == ThreadPoolExecutor
                cls._thread_pool = external_thread_pool
        else:
            cls._thread_pool = ThreadPoolExecutor( VopsProvider.get_number_of_threads( number_of_threads ) )
        cls._number_of_threads = number_of_threads
        cls._blocks_per_request = blocks_per_request
        cls.currently_received_block =  cls._start_block - 1

        # prepare quques and threads
        for i in range( 0, number_of_threads):
                cls._responses_queues.append( queue.Queue( maxsize = 50 ) )

    def get_number_of_threads( number_of_threads ):
        """Return number of used thread if user want to collects virtual operations in some threads number
           number_of_threads - how many threads will ask for vops
        """
        return number_of_threads + 1 # +1 because of a thread for collecting blocks from threads

    def thread_body_get_block( cls, blocks_shift ):
        try:
            for block in range ( cls._start_block + blocks_shift * cls._blocks_per_request, cls._max_block + cls._blocks_per_request, cls._number_of_threads * cls._blocks_per_request ):
                if not cls._breaker():
                    return;

                results = cls._client.enum_virtual_ops(cls._conf, block, block + cls._blocks_per_request)
                while cls._breaker():
                    try:
                        cls._responses_queues[ blocks_shift ].put( results, True, 1 )
                        break
                    except queue.Full:
                        continue
        except:
            cls._exception_reporter()
            raise

    def _fill_queue_with_no_vops(cls, queue_for_vops, number_of_no_vops):
        for vop in range( 0, number_of_no_vops):
            while cls._breaker():
                try:
                    queue_for_vops.put( [], True, 1 )
                    cls.currently_received_block += 1
                    if cls.currently_received_block >= (cls._max_block - 1):
                        return True
                    break
                except queue.Full:
                    continue
        return False

    def thread_body_blocks_collector( cls, queue_for_vops ):
        try:
            while cls._breaker():
                # take in order all vops from threads queues
                for vops_queue in range ( 0, cls._number_of_threads ):
                    if not cls._breaker():
                        return;
                    while cls._breaker():
                        try:
                            vops = cls._responses_queues[ vops_queue ].get( True, 1)
                            cls._responses_queues[ vops_queue ].task_done()
                            #split blocks range
                            if not vops:
                                if cls._fill_queue_with_no_vops( queue_for_vops, cls._blocks_per_request ):
                                    return;
                            else:
                                for block in vops:
                                    if cls._fill_queue_with_no_vops( queue_for_vops, block - ( cls.currently_received_block + 1 ) ):
                                        return;
                                    vop = vops[ block ]
                                    while cls._breaker():
                                        try:
                                            queue_for_vops.put( vop[ 'ops' ], True, 1 )
                                            cls.currently_received_block += 1
                                            if cls.currently_received_block >= (cls._max_block - 1):
                                                return
                                            break
                                        except queue.Full:
                                            continue
                            break
                        except queue.Empty:
                            continue
        except:
            cls._exception_reporter()
            raise

    def start(cls, queue_for_vops):
        futures = []
        for future_number in range(0, cls._number_of_threads):
            future = cls._thread_pool.submit( cls.thread_body_get_block, future_number  )
            futures.append( future )

        future = cls._thread_pool.submit( cls.thread_body_blocks_collector, queue_for_vops )
        futures.append( future )
        return futures

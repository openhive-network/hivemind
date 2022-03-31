from concurrent.futures import ThreadPoolExecutor
import logging
import queue

from hive.indexer.mock_block_provider import MockBlockProvider
from hive.steem.signal import can_continue_thread, set_exception_thrown

log = logging.getLogger(__name__)


class BlocksProvider:
    """Starts threads which request node for blocks, and collect responses to one queue"""

    def __init__(
        cls,
        http_client,
        number_of_threads,
        blocks_per_request,
        start_block,
        max_block,
        external_thread_pool=None,
    ):
        """
        http_client - object which will ask the node for blocks
        number_of_threads - how many threads will be used to ask for blocks
        start_block - block from which the processing starts
        max_block - last to get block's number
        external_thread_pool - thread pool controlled outside the class
        """

        assert number_of_threads > 0
        assert max_block > start_block
        assert http_client
        assert blocks_per_request >= 1

        cls._responses_queues = []
        cls._start_block = start_block
        cls._max_block = max_block  # to inlude upperbound in results
        cls._http_client = http_client
        if external_thread_pool:
            assert type(external_thread_pool) == ThreadPoolExecutor
            cls._thread_pool = external_thread_pool
        else:
            cls._thread_pool = ThreadPoolExecutor(BlocksProvider.get_number_of_threads(number_of_threads))
        cls._number_of_threads = number_of_threads
        cls._blocks_per_request = blocks_per_request

        # prepare quques and threads
        for i in range(0, number_of_threads):
            cls._responses_queues.append(queue.Queue(maxsize=50))

    def get_number_of_threads(number_of_threads):
        """Return number of used thread if user want to collects blocks in some threads number
        number_of_threads - how many threds will ask for blocks
        """
        return number_of_threads + 1  # +1 because of a thread for collecting blocks from threads

    def thread_body_get_block(cls, blocks_shift):
        try:
            for block in range(
                cls._start_block + blocks_shift * cls._blocks_per_request,
                cls._max_block,
                cls._number_of_threads * cls._blocks_per_request,
            ):
                if not can_continue_thread():
                    return

                results = []
                number_of_expected_blocks = 1

                query_param = [
                    {'block_num': i} for i in range(block, min([block + cls._blocks_per_request, cls._max_block]))
                ]
                number_of_expected_blocks = len(query_param)
                results = cls._http_client.exec('get_block', query_param, True)

                if results:
                    while can_continue_thread():
                        try:
                            cls._responses_queues[blocks_shift].put(results, True, 1)
                            break
                        except queue.Full:
                            continue
        except:
            set_exception_thrown()
            raise

    def thread_body_blocks_collector(cls, queue_for_blocks):
        try:
            currently_received_block = cls._start_block - 1
            while can_continue_thread():
                # take in order all blocks from threads queues
                for blocks_queue in range(0, cls._number_of_threads):
                    if not can_continue_thread():
                        return
                    while can_continue_thread():
                        try:
                            blocks = cls._responses_queues[blocks_queue].get(True, 1)
                            cls._responses_queues[blocks_queue].task_done()
                            # split blocks range

                            for block in blocks:
                                if 'block' in block:
                                    MockBlockProvider.set_last_real_block_num_date(
                                        currently_received_block + 1,
                                        block['block']['timestamp'],
                                        block['block']['block_id'],
                                    )

                                block_mock = MockBlockProvider.get_block_data(currently_received_block + 1, True)

                                if block_mock is not None:
                                    if 'block' in block:
                                        block["block"]["transactions"].extend(block_mock["transactions"])
                                    else:
                                        block["block"] = block_mock
                                        log.warning(
                                            f"Pure mock block: id {block_mock['block_id']}, previous {block_mock['previous']}"
                                        )
                                block_for_queue = None if not 'block' in block else block['block']

                                while can_continue_thread():
                                    try:
                                        queue_for_blocks.put(block_for_queue, True, 1)
                                        currently_received_block += 1
                                        if currently_received_block >= (cls._max_block - 1):
                                            return
                                        break
                                    except queue.Full:
                                        continue
                            break
                        except queue.Empty:
                            continue
        except:
            set_exception_thrown()
            raise

    def start(cls, queue_for_blocks):
        futures = []
        for future_number in range(0, cls._number_of_threads):
            future = cls._thread_pool.submit(cls.thread_body_get_block, future_number)
            futures.append(future)

        future = cls._thread_pool.submit(cls.thread_body_blocks_collector, queue_for_blocks)
        futures.append(future)
        return futures

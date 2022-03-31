from concurrent.futures import ThreadPoolExecutor
import logging
import queue
from typing import Optional

from hive.conf import Conf
from hive.steem.client import SteemClient
from hive.steem.signal import can_continue_thread, set_exception_thrown

log = logging.getLogger(__name__)


class VopsProvider:
    """Starts threads which request node for blocks, and collect responses to one queue"""

    def __init__(
        self,
        conf: Conf,
        client: SteemClient,
        number_of_threads: int,
        blocks_per_request: int,
        start_block: int,
        max_block: int,
        external_thread_pool: Optional[ThreadPoolExecutor] = None,
    ):
        """
        conf - configuration
        steem client - object which will ask the node for blocks
        number_of_threads - how many threads will be used to ask for blocks
        start_block - block from which the processing starts
        max_block - last to get block's number
        external_thread_pool - thread pool controlled outside the class
        """

        assert conf
        assert number_of_threads > 0
        assert max_block > start_block
        assert client
        assert blocks_per_request >= 1

        self._conf = conf
        self._responses_queues = []
        self._start_block = start_block
        self._max_block = max_block  # to inlude upperbound in results
        self._client = client
        if external_thread_pool:
            assert type(external_thread_pool) == ThreadPoolExecutor
            self._thread_pool = external_thread_pool
        else:
            self._thread_pool = ThreadPoolExecutor(VopsProvider.get_number_of_threads(number_of_threads))
        self._number_of_threads = number_of_threads
        self._blocks_per_request = blocks_per_request
        self.currently_received_block = self._start_block - 1

        # prepare quques and threads
        for i in range(0, number_of_threads):
            self._responses_queues.append(queue.Queue(maxsize=50))

    @staticmethod
    def get_number_of_threads(number_of_threads):
        """Return number of used thread if user want to collects virtual operations in some threads number
        number_of_threads - how many threads will ask for vops
        """
        return number_of_threads + 1  # +1 because of a thread for collecting blocks from threads

    @staticmethod
    def get_virtual_operation_for_blocks(client, conf, start_block_num, number_of_blocks):
        return client.enum_virtual_ops(conf, start_block_num, start_block_num + number_of_blocks)

    def thread_body_get_block(self, blocks_shift):
        try:
            for block in range(
                self._start_block + blocks_shift * self._blocks_per_request,
                self._max_block + self._blocks_per_request,
                self._number_of_threads * self._blocks_per_request,
            ):
                if not can_continue_thread():
                    return

                results = VopsProvider.get_virtual_operation_for_blocks(
                    self._client, self._conf, block, self._blocks_per_request
                )
                while can_continue_thread():
                    try:
                        self._responses_queues[blocks_shift].put(results, True, 1)
                        break
                    except queue.Full:
                        continue
        except:
            set_exception_thrown()
            raise

    def _fill_queue_with_no_vops(self, queue_for_vops, number_of_no_vops):
        for vop in range(0, number_of_no_vops):
            while can_continue_thread():
                try:
                    queue_for_vops.put([], True, 1)
                    self.currently_received_block += 1
                    if self.currently_received_block >= (self._max_block - 1):
                        return True
                    break
                except queue.Full:
                    continue
        return False

    def thread_body_blocks_collector(self, queue_for_vops):
        try:
            while can_continue_thread():
                # take in order all vops from threads queues
                for vops_queue in range(0, self._number_of_threads):
                    if not can_continue_thread():
                        return
                    while can_continue_thread():
                        try:
                            vops = self._responses_queues[vops_queue].get(True, 1)
                            self._responses_queues[vops_queue].task_done()
                            # split blocks range
                            if not vops:
                                if self._fill_queue_with_no_vops(queue_for_vops, self._blocks_per_request):
                                    return
                            else:
                                for block in vops:
                                    if self._fill_queue_with_no_vops(
                                        queue_for_vops, block - (self.currently_received_block + 1)
                                    ):
                                        return
                                    vop = vops[block]
                                    while can_continue_thread():
                                        try:
                                            queue_for_vops.put(vop['ops'], True, 1)
                                            self.currently_received_block += 1
                                            if self.currently_received_block >= (self._max_block - 1):
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

    def start(self, queue_for_vops):
        futures = []
        for future_number in range(0, self._number_of_threads):
            future = self._thread_pool.submit(self.thread_body_get_block, future_number)
            futures.append(future)

        future = self._thread_pool.submit(self.thread_body_blocks_collector, queue_for_vops)
        futures.append(future)
        return futures

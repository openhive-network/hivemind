"""Streams incoming blocks from the Steem blockchain."""

import logging
from time import sleep

from hive.steem.block.one_block_provider import OneBlockProviderFactory
from hive.steem.block.schedule import BlockSchedule
from hive.steem.signal import can_continue_thread

log = logging.getLogger(__name__)


class ForkException(Exception):
    """Raised when a non-trivial fork is encountered."""

    pass


class MicroForkException(Exception):
    """Raised when a potentially trivial fork is encountered."""

    pass


class BlockQueue:
    """A block queue with fork detection and adjustable length buffer.

    The buffer can be length 0 (no fork protection) or more -- for
    example, a length of 2 would capture vast majority of microforks.

    Throws ForkException; or MicroForkException if the fork seems to be
    confined to the buffer (ie easily recoverable by restarting stream)."""

    def __init__(self, max_size, prev_block):
        self._max_size = max_size
        self._prev = prev_block
        self._queue = []

    def push(self, block):
        """Verify block links, then push -- and shift if buffer full.

        If a fork is encountered and there are blocks in the queue, a
        MicroForkException is thrown; otherwise, ForkException."""
        if self._prev.get_hash() != block.get_previous_block_hash():
            fork = f"{self._prev}--> {block.get_previous_block_hash()}->{block.get_hash()}"
            if self._queue:  # if using max_size>0, fork might be in buffer only
                buff = self.size()
                alert = "NOTIFYALERT " if buff < self._max_size else ""
                raise MicroForkException("%squeue:%d %s" % (alert, buff, fork))
            raise ForkException("NOTIFYALERT fork " + fork)

        self._prev = block
        self._queue.append(block)
        if self.size() > self._max_size:
            return self._queue.pop(0)

    def size(self):
        """Count blocks in our queue."""
        return len(self._queue)


class BlockStream:
    """ETA-based block streamer."""

    @classmethod
    def stream(cls, conf, client, start_block, min_gap=0, max_gap=100, do_stale_block_check=True):
        """Instantiates a BlockStream and returns a generator."""
        streamer = BlockStream(conf, client, min_gap, max_gap)
        return streamer.start(start_block, do_stale_block_check)

    def __init__(self, conf, client, min_gap=0, max_gap=100):
        assert not (min_gap < 0 or min_gap > 100)
        self._client = client
        self._min_gap = min_gap
        self._max_gap = max_gap
        self._conf = conf

    def _gap_ok(self, curr, head):
        """Ensures gap between curr and head is within limits (max_gap)."""
        return not self._max_gap or head - curr < self._max_gap

    def start(self, start_block, do_stale_block_check):
        """Stream blocks starting from `start_block`.

        Will run forever unless `max_gap` is specified and exceeded.
        """

        with OneBlockProviderFactory(self._conf, self._client) as one_block_provider:
            curr = start_block
            head = self._client.head_block()
            prev = one_block_provider.get_block(curr - 1)

            assert prev

            queue = BlockQueue(self._min_gap, prev)

            schedule = BlockSchedule(head, do_stale_block_check)

            while self._gap_ok(curr, head):
                if not can_continue_thread():
                    return
                head = schedule.wait_for_block(curr)
                block = one_block_provider.get_block(curr)

                schedule.check_block(curr, block)

                if not block:
                    sleep(0.5)
                    continue

                popped = queue.push(block)
                if popped:
                    yield popped

                curr += 1

            log.warning("gap exceeds %d", self._max_gap)

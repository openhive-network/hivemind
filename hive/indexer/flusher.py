"""Flush blocks data."""

import concurrent
from concurrent.futures import ThreadPoolExecutor
import logging
from typing import Callable, List, Tuple, Any

from hive.utils.stats import FlushStatusManager as FSM

log = logging.getLogger(__name__)


def time_collector(func: Callable, *args, **kwargs) -> Tuple[Any, float]:
    """Measure execution time of a function."""
    start_time = FSM.start()
    result = func(*args, **kwargs)
    elapsed_time = FSM.stop(start_time)
    return result, elapsed_time


def process_flush_items(
    items: List[Tuple[str, Callable, Any, ...]]
) -> None:
    """Process a list of flush items, measuring their execution time.

    Args:
        items: List of tuples containing (description, function, class, ...) where additional
              arguments are passed to the function
    """
    for item in items:
        description, f, c, *args = item
        try:
            (n, elapsed_time) = time_collector(f, *args)
            log.info(
                "%s flush executed in: %.4f s",
                description,
                elapsed_time
            )
        except Exception as exc:
            log.error(f'{description!r} generated an exception: {exc}')
            raise exc


def process_flush_items_threaded(
    items: List[Tuple[str, Callable, Any, ...]]
) -> None:
    """Process a list of flush items in parallel using a thread pool.

    Args:
        items: List of tuples containing (description, function, class, ...) where additional
              arguments are passed to the function
    """
    completed_threads = 0
    pool = ThreadPoolExecutor(max_workers=len(items))

    flush_futures = {
        pool.submit(time_collector, f, *args): (description, c)
        for (description, f, c, *args) in items
    }

    for future in concurrent.futures.as_completed(flush_futures):
        (description, c) = flush_futures[future]
        completed_threads = completed_threads + 1
        try:
            (n, elapsed_time) = future.result()
            assert n is not None
            assert not c.sync_tx_active()

            FSM.flush_stat(description, elapsed_time, n)

        except Exception as exc:
            log.error(f'{description!r} generated an exception: {exc}')
            raise exc

    pool.shutdown()
    assert completed_threads == len(items)

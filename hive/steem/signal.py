"""Hive signal handling."""

import logging

from signal import SIGINT
from atomic import AtomicLong


log = logging.getLogger(__name__)

EXCEPTION_THROWN = AtomicLong(0)
FINISH_SIGNAL_DURING_SYNC = AtomicLong(0)


def finish_signals_handler(signal, frame):
    global FINISH_SIGNAL_DURING_SYNC
    FINISH_SIGNAL_DURING_SYNC += 1
    log.info("""
                  **********************************************************
                  CAUGHT {}. PLEASE WAIT... PROCESSING DATA IN QUEUES...
                  **********************************************************
    """.format( "SIGINT" if signal == SIGINT else "SIGTERM" ) )

def set_exception_thrown():
    global EXCEPTION_THROWN
    EXCEPTION_THROWN += 1

def can_continue_thread():
    return EXCEPTION_THROWN.value == 0 and FINISH_SIGNAL_DURING_SYNC.value == 0

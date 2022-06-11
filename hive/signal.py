"""Hive signal handling."""

import logging
from signal import SIGINT, signal, SIGTERM

from atomic import AtomicLong

log = logging.getLogger(__name__)

EXCEPTION_THROWN = AtomicLong(0)
FINISH_SIGNAL_DURING_SYNC = AtomicLong(0)


default_sigint_handler = None
default_sigterm_handler = None


def set_custom_signal_handlers():
    global default_sigint_handler
    global default_sigterm_handler
    default_sigint_handler = signal(SIGINT, custom_signals_handler)
    default_sigterm_handler = signal(SIGTERM, custom_signals_handler)


def restore_default_signal_handlers():
    signal(SIGINT, default_sigint_handler)
    signal(SIGTERM, default_sigterm_handler)


def custom_signals_handler(signal, frame):
    global FINISH_SIGNAL_DURING_SYNC
    FINISH_SIGNAL_DURING_SYNC += 1
    log.info(
        f"""
                  **********************************************************
                  CAUGHT {'SIGINT' if signal == SIGINT else 'SIGTERM'}. PLEASE WAIT... PROCESSING DATA IN QUEUES...
                  **********************************************************
    """
    )


def set_exception_thrown():
    global EXCEPTION_THROWN
    EXCEPTION_THROWN += 1


def can_continue_thread():
    return EXCEPTION_THROWN.value == 0 and FINISH_SIGNAL_DURING_SYNC.value == 0

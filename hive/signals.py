"""Hive signal handling."""

import logging
import threading
from signal import SIGINT, SIGTERM, signal

log = logging.getLogger(__name__)


class AtomicCounter:
    """Thread-safe counter using stdlib threading.Lock()."""

    def __init__(self, initial=0):
        self._value = initial
        self._lock = threading.Lock()

    @property
    def value(self):
        with self._lock:
            return self._value

    def __iadd__(self, other):
        with self._lock:
            self._value += other
        return self


EXCEPTION_THROWN = AtomicCounter(0)
FINISH_SIGNAL_DURING_SYNC = AtomicCounter(0)


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

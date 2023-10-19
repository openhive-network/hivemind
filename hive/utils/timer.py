"""Timer for reporting progress on long batch operations."""

from functools import wraps
import logging
from time import perf_counter as perf

from hive.utils.normalize import secs_to_str

log = logging.getLogger(__name__)


# timeit decorator for measuring method execution time
def time_it(method):
    @wraps(method)
    def time_method(*args, **kwargs):
        start_time = perf()
        result = method(*args, **kwargs)
        log.info("%s executed in %.4f s", method.__name__, perf() - start_time)
        return result

    return time_method


class Timer:
    """Times long routines, printing status and ETA.

    Routines are split into batches; each consisting of 1+ laps.

    `total` - total number of items being processed
    `entity` - name of entity being processed
    `laps` - list of labels, for ops/s output per lap
    `full_total` - total items to process, outside of
                   (and including) this invocation. [optional]
    """

    # pylint: disable=too-many-instance-attributes

    # Name of entity, lap units (e.g. rps, wps), total items in job
    _entity = []
    _lap_units = []
    _total = None
    _full_total = None
    _start_time = None

    # Lap checkpoints, # processed, last # processed
    _laps = []
    _processed = 0
    _last_items = 0

    def __init__(self, total=None, entity='', laps=None, full_total=None):
        self._entity = entity
        self._lap_units = laps or []
        self._total = total
        self._full_total = full_total or total
        self._start_time = perf()

    def batch_start(self):
        """Signal new batch; call at top of loop."""
        self._laps = []
        self.batch_lap()

    def batch_lap(self):
        """Signal movement to next task within batch."""
        self._laps.append(perf())

    def batch_finish(self, ops=None):
        """Signal end of batch."""
        self.batch_lap()
        self._last_items = ops
        self._processed += ops

    def batch_status(self, prefix=None):
        """Generate status line."""
        if prefix:
            out = prefix
        else:
            # " -- post 1 of 10"
            out = " -- %s %d of %d" % (self._entity, self._processed, self._full_total)

        # " (3/s, 4rps, 5wps) -- "
        rates = []
        for i, unit in enumerate(['/s', *self._lap_units]):
            rates.append('%d%s' % (self._rate(i), unit))
        out += f" ({', '.join(rates)}) -- "

        if self._processed < self._total:
            out += f"eta {self._eta()}"
        else:
            total_time = self._laps[-1] - self._start_time
            out += f"done in {secs_to_str(total_time)}, avg rate: {self._total / total_time:.1f}/s"

        return out

    def _rate(self, lap_idx=None):
        """Get the rate of last batch's lap_idx, pass None for overall."""
        secs = self._elapsed(lap_idx)
        return self._last_items / secs

    def _eta(self):
        """Time to finish, based on most recent batch."""
        left = self._full_total - self._processed
        secs = left / self._rate()
        return secs_to_str(secs)

    def _elapsed(self, lap_idx=None):
        if not lap_idx:
            return self._laps[-1] - self._laps[0]
        return self._laps[lap_idx] - self._laps[lap_idx - 1]

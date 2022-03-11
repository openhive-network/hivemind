"""Tracks SQL timing stats and prints results periodically or on exit."""

import atexit
import logging
from os import getpid
from queue import Queue
from time import perf_counter as perf

from psutil import pid_exists

from hive.utils.system import colorize, peak_usage_mb

log = logging.getLogger(__name__)


class BroadcastObject:
    def __init__(self, category: str, value, unit):
        self.category = category
        self.value = value
        self.unit = unit

    def name(self):
        ret = ""
        for c in self.category:
            if c.isalnum():
                ret += c
            else:
                ret += "_"
        return f"hivemind_{ret}"

    def debug(self):
        log.debug(f"{self.name()}_{self.unit}: {self.value :.2f}")

    def __repr__(self):
        return self.__str__()

    def __str__(self):
        return str(self.__dict__)


class PrometheusClient:
    deamon = None
    logs_to_broadcast = Queue()

    @staticmethod
    def work(port, pid):
        try:
            import prometheus_client as prom

            prom.start_http_server(port)

            gauges = {}

            while pid_exists(pid):
                value: BroadcastObject = PrometheusClient.logs_to_broadcast.get(True)
                value.debug()
                value_name = value.name()

                if value_name not in gauges.keys():
                    gauge = prom.Gauge(value_name, '', unit=value.unit)
                    gauge.set(value.value)
                    gauges[value_name] = gauge
                else:
                    gauges[value_name].set(value.value)

        except Exception as e:
            log.error(f"Prometheus logging failed. Exception\n {e}")

    def __init__(self, port):
        if port is None:
            return
        else:
            port = int(port)
        if PrometheusClient.deamon is None:
            try:
                import prometheus_client
            except ImportError:
                log.warn("Failed to import prometheus client. Online stats disabled")
                return
            from threading import Thread

            PrometheusClient.deamon = Thread(target=PrometheusClient.work, args=[port, getpid()], daemon=True)
            PrometheusClient.deamon.start()

    @staticmethod
    def broadcast(obj):
        if PrometheusClient.deamon is None:
            return
        if type(obj) == type(list()):
            for v in obj:
                PrometheusClient.broadcast(v)
        elif type(obj) == type(BroadcastObject('', '', '')):
            PrometheusClient.logs_to_broadcast.put(obj)
        else:
            raise Exception(f"Not expected type. Should be list or BroadcastObject, but: {type(obj)} given")


class Stat:
    def __init__(self, time):
        self.time = time

    def update(self, other):
        assert type(self) == type(other)
        attributes = self.__dict__
        oatte = other.__dict__
        for key, val in attributes.items():
            setattr(self, key, oatte[key] + val)
        return self

    def __repr__(self):
        return self.__dict__

    def __lt__(self, other):
        return self.time < other.time

    def broadcast(self, name):
        return BroadcastObject(name, self.time, 's')


class StatusManager:

    # Fully abstract class
    def __init__(self):
        assert False

    @staticmethod
    def start():
        return perf()

    @staticmethod
    def stop(start: float):
        return perf() - start

    @staticmethod
    def merge_dicts(od1, od2, broadcast: bool = False, total_broadcast: bool = True):
        if od2 is not None:
            for k, v in od2.items():
                if k in od1:
                    od1[k].update(v)
                else:
                    od1[k] = v

                if broadcast:
                    PrometheusClient.broadcast(v.broadcast(k))

                if total_broadcast:
                    PrometheusClient.broadcast(od1[k].broadcast(f"{k}_total"))

        return od1

    @staticmethod
    def log_dict(col: dict) -> float:
        sorted_stats = sorted(col.items(), key=lambda kv: kv[1], reverse=True)
        measured_time = 0.0
        for (k, v) in sorted_stats:
            log.info(f"`{k}`: {v}")
            measured_time += v.time
        return measured_time

    @staticmethod
    def print_row():
        log.info("#" * 20)


class OPStat(Stat):
    def __init__(self, time, count):
        super().__init__(time)
        self.count = count

    def __str__(self):
        return f"Processed {self.count :.0f} times in {self.time :.5f} seconds"

    def broadcast(self, name: str):
        n = name.lower()
        if not n.endswith('operation'):
            n = f"{n}_operation"
        return list([super().broadcast(n), BroadcastObject(n + "_count", self.count, 'b')])


class OPStatusManager(StatusManager):
    # Summary for whole sync
    global_stats = {}

    # Currently processed blocks stats, merged to global stats, after `next_block`
    cpbs = {}

    @staticmethod
    def op_stats(name, time, processed=1):
        if name in OPStatusManager.cpbs.keys():
            OPStatusManager.cpbs[name].time += time
            OPStatusManager.cpbs[name].count += processed
        else:
            OPStatusManager.cpbs[name] = OPStat(time, processed)

    @staticmethod
    def next_blocks():
        OPStatusManager.global_stats = StatusManager.merge_dicts(
            OPStatusManager.global_stats, OPStatusManager.cpbs, True
        )
        OPStatusManager.cpbs.clear()

    @staticmethod
    def log_global(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(OPStatusManager.global_stats)
        log.info(f"Total time for processing operations time: {tm :.4f}s.")
        return tm

    @staticmethod
    def log_current(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(OPStatusManager.cpbs)
        log.info(f"Current time for processing operations time: {tm :.4f}s.")
        return tm


class FlushStat(Stat):
    def __init__(self, time, pushed):
        super().__init__(time)
        self.pushed = pushed

    def __str__(self):
        return f"Pushed {self.pushed :.0f} records in {self.time :.4f} seconds"

    def broadcast(self, name: str):
        n = f"flushing_{name.lower()}"
        return list([super().broadcast(n), BroadcastObject(n + "_items", self.pushed, 'b')])


class FlushStatusManager(StatusManager):
    # Summary for whole sync
    global_stats = {}

    # Currently processed blocks stats, merged to global stats, after `next_block`
    current_flushes = {}

    @staticmethod
    def flush_stat(name, time, pushed):
        if name in FlushStatusManager.current_flushes.keys():
            FlushStatusManager.current_flushes[name].time += time
            FlushStatusManager.current_flushes[name].pushed += pushed
        else:
            FlushStatusManager.current_flushes[name] = FlushStat(time, pushed)

    @staticmethod
    def next_blocks():
        FlushStatusManager.global_stats = StatusManager.merge_dicts(
            FlushStatusManager.global_stats, FlushStatusManager.current_flushes, True
        )
        FlushStatusManager.current_flushes.clear()

    @staticmethod
    def log_global(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(FlushStatusManager.global_stats)
        log.info(f"Total flushing time: {tm :.4f}s.")
        return tm

    @staticmethod
    def log_current(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(FlushStatusManager.current_flushes)
        log.info(f"Current flushing time: {tm :.4f}s.")
        return tm


class FinalStat(Stat):
    def __init__(self, time):
        super().__init__(time)

    def __str__(self):
        return f"Processed final operations in {self.time :.4f} seconds"

    def broadcast(self, name: str):
        n = f"flushing_{name.lower()}"
        return list([super().broadcast(n), BroadcastObject(n + "_items", '', 'b')])


class FinalOperationStatusManager(StatusManager):
    # Summary for whole sync
    global_stats = {}

    # Currently processed blocks stats, merged to global stats, after `next_block`
    current_finals = {}

    @staticmethod
    def final_stat(name, time):
        if name in FinalOperationStatusManager.current_finals.keys():
            FinalOperationStatusManager.current_finals[name].time += time
        else:
            FinalOperationStatusManager.current_finals[name] = FinalStat(time)

    @staticmethod
    def log_current(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(FinalOperationStatusManager.current_finals)
        log.info(f"Current final processing time: {tm :.4f}s.")
        return tm

    @staticmethod
    def clear():
        FinalOperationStatusManager.current_finals.clear()


class WaitStat(Stat):
    def __init__(self, time):
        super().__init__(time)

    def __str__(self):
        return f"Waited {self.time :.4f} seconds"


class WaitingStatusManager(StatusManager):
    # Summary for whole sync
    global_stats = {}

    # Currently processed blocks stats, merged to global stats, after `next_block`
    current_waits = {}

    @staticmethod
    def wait_stat(name, time):
        if name in WaitingStatusManager.current_waits.keys():
            WaitingStatusManager.current_waits[name].time += time
        else:
            WaitingStatusManager.current_waits[name] = WaitStat(time)

    @staticmethod
    def next_blocks():
        WaitingStatusManager.global_stats = StatusManager.merge_dicts(
            WaitingStatusManager.global_stats, WaitingStatusManager.current_waits, True
        )
        WaitingStatusManager.current_waits.clear()

    @staticmethod
    def log_global(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(WaitingStatusManager.global_stats)
        log.info(f"Total waiting time: {tm :.4f}s.")
        return tm

    @staticmethod
    def log_current(label: str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_dict(WaitingStatusManager.current_waits)
        log.info(f"Current waiting time: {tm :.4f}s.")
        return tm


def minmax(collection: dict, blocks: int, time: float, _from: int):
    value = blocks / time
    _to = _from + blocks
    PrometheusClient.broadcast(BroadcastObject('block_processing_rate', value, 'bps'))
    if len(collection.keys()) == 0:

        collection['min'] = value
        collection['min_from'] = _from
        collection['min_to'] = _to

        collection['max'] = value
        collection['max_from'] = _from
        collection['max_to'] = _to

    else:

        mn = min(collection['min'], value)
        if mn == value:
            collection['min'] = value
            collection['min_from'] = _from
            collection['min_to'] = _to
        mx = max(collection['max'], value)
        if mx == value:
            collection['max'] = value
            collection['max_from'] = _from
            collection['max_to'] = _to

    return collection


def _normalize_sql(sql, maxlen=180):
    """Collapse whitespace and middle-truncate if needed."""
    out = ' '.join(sql.split())
    if len(out) > maxlen:
        i = int(maxlen / 2 - 4)
        out = out[0:i] + ' ... ' + out[-i:None]
    return out


class StatsAbstract:
    """Tracks service call timings"""

    def __init__(self, service):
        self._service = service
        self.clear()

    def add(self, call, ms, batch_size=1):
        """Record a call's duration."""
        try:
            key = self._calls[call]
            key[0] += ms
            key[1] += batch_size
        except KeyError:
            self._calls[call] = [ms, batch_size]
        self.check_timing(call, ms, batch_size)
        self._ms += ms

    def check_timing(self, call, ms, batch_size):
        """Override for service-specific QA"""

    def ms(self):
        """Get total time spent in service"""
        return self._ms

    def clear(self):
        """Clear accumulators"""
        self._calls = {}
        self._ms = 0.0

    def table(self, count=40):
        """Generate a desc list of (call, total_ms, call_count) tuples."""
        top = sorted(self._calls.items(), key=lambda x: -x[1][0])
        return [(call, *vals) for (call, vals) in top[:count]]

    def report(self, parent_secs):
        """Emit a table showing top calls by time spent."""
        if not self._calls:
            return

        total_ms = parent_secs * 1000
        log.info(
            "Service: %s -- %ds total (%.1f%%)", self._service, round(self._ms / 1000), 100 * (self._ms / total_ms)
        )

        log.info('%7s %9s %9s %9s', '-pct-', '-ttl-', '-avg-', '-cnt-')
        for call, ms, reqs in self.table(40):
            try:
                avg = ms / reqs
                millisec = ms / self._ms
            except ZeroDivisionError as ex:
                avg = 0.0
                millisec = 0.0
            if reqs == 0:
                reqs = 1
            log.info("% 6.1f%% % 7dms % 9.2f % 8dx -- %s", 100 * millisec, ms, avg, reqs, call)
        self.clear()


class SteemStats(StatsAbstract):
    """Tracks Steem client call timings."""

    # Assumed HTTP overhead (ms); subtract prior to par check
    PAR_HTTP_OVERHEAD = 75

    # Reporting threshold (x * par)
    PAR_THRESHOLD = 1.1

    # Thresholds for critical call timing (ms)
    PAR_STEEMD = {
        'get_dynamic_global_properties': 20,
        'get_block': 50,
        'get_blocks_batch': 5,
        'get_content': 4,
        'get_order_book': 20,
        'get_feed_history': 20,
        'lookup_accounts': 1000,
        'get_comment_pending_payouts': 1000,
        'get_ops_in_block': 500,
        'enum_virtual_ops': 1000,
    }

    def __init__(self):
        super().__init__('steem')

    def check_timing(self, call, ms, batch_size):
        """Warn if a request (accounting for batch size) is too slow."""
        if call == 'get_block' and batch_size > 1:
            call = 'get_blocks_batch'
        per = int((ms - self.PAR_HTTP_OVERHEAD) / batch_size)
        par = self.PAR_STEEMD[call]
        over = per / par
        if over >= self.PAR_THRESHOLD:
            out = "[STEEM][%dms] %s[%d] -- %.1fx par (%d/%d)" % (ms, call, batch_size, over, per, par)
            log.warning(colorize(out))


class DbStats(StatsAbstract):
    """Tracks database query timings."""

    SLOW_QUERY_MS = 250
    LOGGING_TRESHOLD = 50

    def __init__(self):
        super().__init__('db')

    def check_timing(self, call, ms, batch_size):
        """Warn if any query is slower than defined threshold."""

        if ms > self.LOGGING_TRESHOLD:
            log.warning("[SQL][%dms] %s", ms, call)
            if ms > self.SLOW_QUERY_MS:
                out = "[SQL][%dms] %s" % (ms, call[:250])
                log.warning(colorize(out))


class Stats:
    """Container for steemd and db timing data."""

    PRINT_THRESH_MINS = 1

    COLLECT_DB_STATS = 0
    COLLECT_NODE_STATS = 0

    _db = DbStats()
    _steemd = SteemStats()
    _secs = 0.0
    _idle = 0.0
    _start = perf()

    @classmethod
    def log_db(cls, sql, secs):
        """Log a database query. Incoming SQL is normalized."""
        if cls.COLLECT_DB_STATS:
            cls._db.add(_normalize_sql(sql), secs * 1000)
            cls.add_secs(secs)

    @classmethod
    def log_steem(cls, method, secs, batch_size=1):
        """Log a steemd call."""
        if cls.COLLECT_NODE_STATS:
            cls._steemd.add(method, secs * 1000, batch_size)
            cls.add_secs(secs)

    @classmethod
    def log_idle(cls, secs):
        """Track idle time (e.g. sleeping until next block)"""
        cls._idle += secs

    @classmethod
    def add_secs(cls, secs):
        """Add to total ms elapsed; print if threshold reached."""
        cls._secs += secs
        if cls._secs > cls.PRINT_THRESH_MINS * 60:
            cls.report()
            cls._secs = 0
            cls._idle = 0
            cls._start = perf()

    @classmethod
    def report(cls):
        """Emit a timing report for tracked services."""
        if not cls._secs:
            return  # nothing to report
        total = perf() - cls._start
        non_idle = total - cls._idle
        log.info(
            "cumtime %ds (%.1f%% of %ds). %.1f%% idle. peak %dmb.",
            cls._secs,
            100 * cls._secs / non_idle,
            non_idle,
            100 * cls._idle / total,
            peak_usage_mb(),
        )
        if cls._secs > 1:
            cls._db.report(cls._secs)
            cls._steemd.report(cls._secs)


atexit.register(Stats.report)

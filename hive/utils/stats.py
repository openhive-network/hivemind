"""Tracks SQL timing stats and prints results periodically or on exit."""

import atexit
import logging

from queue import Queue
from time import perf_counter as perf
from hive.utils.system import colorize, peak_usage_mb
from psutil import pid_exists
from os import getpid
from threading import Thread

log = logging.getLogger(__name__)

class BroadcastObject:
    def __init__(self, category : str, value, unit):
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
    def work( port, pid ):
        try:
            import prometheus_client as prom
            prom.start_http_server(port)

            gauges = {}

            while pid_exists(pid):
                value : BroadcastObject = PrometheusClient.logs_to_broadcast.get()
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
            deamon = Thread(target=PrometheusClient.work, args=[ port, getpid() ], daemon=True)
            deamon.start()

    @staticmethod
    def broadcast(obj):
        if type(obj) == type(list()):
            for v in obj:
                PrometheusClient.broadcast(v)
        elif type(obj) == type(BroadcastObject('', '', '')):
            PrometheusClient.logs_to_broadcast.put(obj)
        else:
            raise Exception(f"Not expexcted type. Should be list or BroadcastObject, but: {type(obj)} given")

class Stat:
    def __init__(self, time):
        self.time = time

    def update_time(self, other):
        self.time += other.time

    def __repr__(self):
        return str(self.__dict__)

    def __lt__(self, other):
        return self.time < other.time

    def broadcast(self, name):
        return BroadcastObject(name, self.time, 's')

class StatusManager:

    global_stats = {}
    local_stats = {}
    deamon : Thread = None
    metrics_to_save = Queue()
    __join = False

    def __init__(self):
        if StatusManager.deamon is None:
            StatusManager.deamon = Thread(target=StatusManager.__work, args=[ getpid() ], daemon=True)
            # StatusManager.metrics_to_save.put(None)
            StatusManager.deamon.start()

    @staticmethod
    def start():
        return perf()

    @staticmethod
    def stop( start : float ):
        return perf() - start

    @staticmethod
    def merge_dicts(od1, od2, broadcast : bool = False, total_broadcast : bool = True):
        if od2 is not None and len(od2) > 0:
            for mgr, values in od2.items():

                if mgr not in od1.keys():
                    od1[mgr] = {}

                for k, v in values.items():
                    if k in od1[mgr]:
                        od1[mgr][k].update(v)
                    else:
                        od1[mgr][k] = v
                    
                    if broadcast:
                        PrometheusClient.broadcast(v.broadcast(k))

                    if total_broadcast:
                        PrometheusClient.broadcast( od1[mgr][k].broadcast( f"{k}_total" ) )

        return od1

    @staticmethod
    def push_value( manager, name, item ):
        if not StatusManager.metrics_started():
            return
        StatusManager.metrics_to_save.put_nowait( {'manager':manager, 'key': name, 'value': item } )

    @staticmethod
    def next_blocks():
        if not StatusManager.metrics_started():
            return
        StatusManager.metrics_to_save.put_nowait(None)

    @staticmethod
    def log_global_dict(mngr : str):
        if mngr not in StatusManager.global_stats.keys():
            return 0
        return StatusManager.log_dict( StatusManager.global_stats[mngr] )

    @staticmethod
    def log_local_dict(mngr : str):
        if mngr not in StatusManager.local_stats.keys():
            return 0
        return StatusManager.log_dict( StatusManager.local_stats[mngr].copy() )

    @staticmethod
    def log_dict(col : dict) -> float:
        if len(col) == 0:
            return 0
        sorted_stats = sorted(col.items(), key=lambda kv: kv[1], reverse=True)
        measured_time = 0.0
        for (k, v) in sorted_stats:
            log.info("`{}`: {}".format(k, v))
            measured_time += v.time
        return measured_time

    @staticmethod
    def metrics_started() -> bool:
        return StatusManager.deamon is not None

    @staticmethod
    def print_row(n : int = 1):
        log.info("#" * 20 * n)

    @staticmethod
    def __work(pid):
        try:
            log.info("stats thread started")
            while pid_exists(pid):
                val : dict = StatusManager.metrics_to_save.get(True, 60)
                if val is None:
                    StatusManager.global_stats = StatusManager.merge_dicts( StatusManager.global_stats, StatusManager.local_stats, True )
                    StatusManager.local_stats.clear()
                    for key in StatusManager.global_stats.keys():
                        StatusManager.local_stats[key] = {}
                else:
                    StatusManager.__add_value( val['manager'], val['key'], val['value'] )
                if StatusManager.metrics_to_save.qsize() == 0 and StatusManager.__join:
                    break
        except Exception as e:
            log.error(f"stats collector thread failed: {e}")

    @staticmethod
    def __add_value( manager, key, value ):
        if manager not in StatusManager.local_stats.keys():
            StatusManager.local_stats[manager] = {}
        
        if key in StatusManager.local_stats[manager].keys():
            StatusManager.local_stats[manager][key].update(value)
        else:
            StatusManager.local_stats[manager][key] = value

    @staticmethod
    def join():
        log.info("joining stats queue...")
        StatusManager.__join = True
        try:
            StatusManager.deamon.join()
        except:
            log.warn("joined with exception")
            return
        log.info("joined successfully")


class OPStat(Stat):
    def __init__(self, time, count):
        super().__init__(time)
        self.count = count

    def __str__(self):
        return f"Processed {self.count :.0f} times in {self.time :.5f} seconds"

    def update(self, other):
        self.update_time(other)
        self.count += other.count

    def broadcast(self, name : str):
        n = name.lower()
        if not n.endswith('operation'):
            n = f"{n}_operation"
        return list([ super().broadcast(n), BroadcastObject(n + "_count", self.count, 'b') ])

class OPStatusManager(StatusManager):

    name_sm = "OPStatusManager"

    @staticmethod
    def op_stats( name, time, processed = 1 ):
        StatusManager.push_value( OPStatusManager.name_sm, name, OPStat(time, processed) )

    @staticmethod
    def log_global(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_global_dict(OPStatusManager.name_sm)
        log.info(f"Total time for processing operations time: {tm :.4f}s.")
        return tm


    @staticmethod
    def log_current(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_local_dict(OPStatusManager.name_sm)
        log.info(f"Current time for processing operations time: {tm :.4f}s.")
        return tm

class FlushStat(Stat):
    def __init__(self, time, pushed):
        super().__init__(time)
        self.pushed = pushed

    def update(self, other):
        self.update_time(other)
        self.pushed += other.pushed

    def __str__(self):
        return f"Pushed {self.pushed :.0f} records in {self.time :.4f} seconds"

    def broadcast(self, name : str):
        n = f"flushing_{name.lower()}"
        return list([ super().broadcast(n), BroadcastObject(n + "_items", self.pushed, 'b') ])

class FlushStatusManager(StatusManager):

    name_sm = "FlushStatusManager"

    @staticmethod
    def flush_stat(name, time, pushed):
        StatusManager.push_value( FlushStatusManager.name_sm, name, FlushStat(time, pushed) )

    @staticmethod
    def log_global(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_global_dict(FlushStatusManager.name_sm)
        log.info(f"Total flushing time: {tm :.4f}s.")
        return tm

    @staticmethod
    def log_current(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_local_dict(FlushStatusManager.name_sm)
        log.info(f"Current flushing time: {tm :.4f}s.")
        return tm

class WaitStat(Stat):
    def __init__(self, time):
        super().__init__(time)

    def update(self, other):
        self.update_time(other)

    def __str__(self):
        return f"Waited {self.time :.4f} seconds"

class WaitingStatusManager(StatusManager):

    name_sm = "WaitingStatusManager"

    @staticmethod
    def wait_stat(name, time):
        StatusManager.push_value( WaitingStatusManager.name_sm, name, WaitStat(time) )

    @staticmethod
    def log_global(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_global_dict(WaitingStatusManager.name_sm)
        log.info(f"Total waiting time: {tm :.4f}s.")
        return tm

    @staticmethod
    def log_current(label : str):
        StatusManager.print_row()
        log.info(label)
        tm = StatusManager.log_local_dict(WaitingStatusManager.name_sm)
        log.info(f"Current waiting time: {tm :.4f}s.")
        return tm

def minmax(collection : dict, blocks : int, time : float, _from : int):
    value = blocks/time
    _to = _from + blocks
    PrometheusClient.broadcast(BroadcastObject('block_processing_rate', value, 'bps'))
    if len(collection.keys())  == 0:

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
        out = (out[0:i] +
               ' ... ' +
               out[-i:None])
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
        log.info("Service: %s -- %ds total (%.1f%%)",
                 self._service,
                 round(self._ms / 1000),
                 100 * (self._ms / total_ms))

        log.info('%7s %9s %9s %9s', '-pct-', '-ttl-', '-avg-', '-cnt-')
        for call, ms, reqs in self.table(40):
            try:
              avg = ms/reqs
              millisec = ms/self._ms
            except ZeroDivisionError as ex:
              avg = 0.0
              millisec = 0.0
            if reqs == 0:
                reqs = 1
            log.info("% 6.1f%% % 7dms % 9.2f % 8dx -- %s",
                     100 * millisec, ms, avg, reqs, call)
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
        'get_comment_pending_payouts':1000,
        'get_ops_in_block':500,
        'enum_virtual_ops':1000
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
            out = ("[STEEM][%dms] %s[%d] -- %.1fx par (%d/%d)"
                   % (ms, call, batch_size, over, per, par))
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
            return # nothing to report
        total = perf() - cls._start
        non_idle = total - cls._idle
        log.info("cumtime %ds (%.1f%% of %ds). %.1f%% idle. peak %dmb.",
                 cls._secs, 100 * cls._secs / non_idle, non_idle,
                 100 * cls._idle / total, peak_usage_mb())
        if cls._secs > 1:
            cls._db.report(cls._secs)
            cls._steemd.report(cls._secs)

atexit.register(Stats.report)

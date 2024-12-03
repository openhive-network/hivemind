"""Async DB adapter for hivemind API."""

import logging
from time import perf_counter as perf

from aiopg.sa import create_engine
import sqlalchemy
from sqlalchemy.engine.url import make_url
import contextvars

from hive.utils.stats import Stats
from hive.server.context import autoexplain_enabled  # Import the shared context variable

logging.getLogger('sqlalchemy.engine').setLevel(logging.WARNING)
log = logging.getLogger(__name__)

def sqltimer(function):
    """Decorator for DB query methods which tracks timing."""

    async def _wrapper(*args, **kwargs):
        start = perf()
        result = await function(*args, **kwargs)
        Stats.log_db(args[1], perf() - start)
        return result

    return _wrapper


class Db:
    """Wrapper for aiopg.sa db driver."""

    @classmethod
    async def create(cls, url, superuser_url):
        """Factory method."""
        instance = Db()
        await instance.init(url, superuser_url)
        return instance

    def __init__(self):
        self.db = None
        self._prep_sql = {}
        self.superuser_db = None  # connection for superuser used for autoexplained statements


    async def init(self, url, superuser_url):
        """Initialize the aiopg.sa engine."""
        conf = make_url(url)
        dsn = {}
        if conf.username:
            dsn['user'] = conf.username
        if conf.database:
            dsn['database'] = conf.database
        if conf.password:
            dsn['password'] = conf.password
        if conf.host:
            dsn['host'] = conf.host
        if conf.port:
            dsn['port'] = conf.port
        if 'application_name' not in conf.query:
            dsn['application_name'] = 'hive_server'
        self.db = await create_engine(**dsn, maxsize=20, **conf.query)

       # Initialize superuser connection pool
        super_conf = make_url(superuser_url)
        super_dsn = {}
        if conf.username:
            super_dsn['user'] = super_conf.username
        if super_conf.database:
            super_dsn['database'] = super_conf.database
        if super_conf.password:
            super_dsn['password'] = super_conf.password
        if super_conf.host:
            super_dsn['host'] = super_conf.host
        if super_conf.port:
            super_dsn['port'] = super_conf.port
        if 'application_name' not in super_conf.query:
            super_dsn['application_name'] = 'hive_server'
        self.superuser_db = await create_engine(**super_dsn, maxsize=5, **super_conf.query)


    def close(self):
        """Close pool."""
        self.db.close()

    async def wait_closed(self):
        """Wait for releasing and closing all acquired connections."""
        await self.db.wait_closed()

    async def _apply_autoexplain(self, conn, use_superuser):
        """Apply auto_explain settings if enabled in the current context."""
        if use_superuser and autoexplain_enabled.get():
            await self.enable_autoexplain(conn)

    @sqltimer
    async def query_all(self, sql, use_superuser=False, **kwargs):
        """Perform a `SELECT n*m`"""
        pool = self.superuser_db if use_superuser else self.db
        async with pool.acquire() as conn:
            await self._apply_autoexplain(conn, use_superuser)
            cur = await self._query(conn, sql, **kwargs)
            res = await cur.fetchall()
        return res

    @sqltimer
    async def query_row(self, sql, use_superuser=False, **kwargs):
        """Perform a `SELECT 1*m`"""
        pool = self.superuser_db if use_superuser else self.db
        async with pool.acquire() as conn:
            await self._apply_autoexplain(conn, use_superuser)
            cur = await self._query(conn, sql, **kwargs)
            res = await cur.first()
        return res

    @sqltimer
    async def query_col(self, sql, use_superuser=False, **kwargs):
        """Perform a `SELECT n*1`"""
        pool = self.superuser_db if use_superuser else self.db
        async with pool.acquire() as conn:
            await self._apply_autoexplain(conn, use_superuser)
            cur = await self._query(conn, sql, **kwargs)
            res = await cur.fetchall()
        return [r[0] for r in res]

    @sqltimer
    async def query_one(self, sql, use_superuser=False, **kwargs):
        """Perform a `SELECT 1*1`"""
        pool = self.superuser_db if use_superuser else self.db
        async with pool.acquire() as conn:
            await self._apply_autoexplain(conn, use_superuser)
            cur = await self._query(conn, sql, **kwargs)
            row = await cur.first()
        return row[0] if row else None

    @sqltimer
    async def query(self, sql, use_superuser=False, **kwargs):
        """Perform a write query"""
        pool = self.superuser_db if use_superuser else self.db
        async with pool.acquire() as conn:
            await self._apply_autoexplain(conn, use_superuser)
            await self._query(conn, sql, **kwargs)

    async def _query(self, conn, sql, **kwargs):
        """Send a query off to SQLAlchemy."""
        try:
            return await conn.execute(self._sql_text(sql), **kwargs)
        except Exception as e:
            log.warning("[SQL-ERR] %s in query %s (%s)", e.__class__.__name__, sql, kwargs)
            raise e
        finally:
            # Reset auto_explain settings after the query
            if autoexplain_enabled.get():
                await self.reset_autoexplain(conn)

    def _sql_text(self, sql):
        if sql in self._prep_sql:
            query = self._prep_sql[sql]
        else:
            query = sqlalchemy.text(sql).execution_options(autocommit=False)
            self._prep_sql[sql] = query
        return query

    async def enable_autoexplain(self, conn):
        """Enable auto_explain for the given connection."""
        commands = [
            #"LOAD 'auto_explain';",
            # we don't have permissions to load this module, so require the auto_explain module
            # to be preloaded in postgresql.conf via:
            #   shared_preload_libraries = 'auto_explain'
            "SET auto_explain.log_nested_statements = ON;",
            "SET auto_explain.log_min_duration = 0;",
            "SET auto_explain.log_format = 'json';",
            "SET auto_explain.log_analyze = ON;",
            "SET auto_explain.log_buffers = ON;",
            "SET auto_explain.log_verbose = ON;",
        ]
        for cmd in commands:
            await conn.execute(cmd)

    async def reset_autoexplain(self, conn):
        """Reset auto_explain settings to their defaults."""
        commands = [
            "RESET auto_explain.log_nested_statements;",
            "RESET auto_explain.log_min_duration;",
            "RESET auto_explain.log_format;",
            "RESET auto_explain.log_analyze;",
            "RESET auto_explain.log_buffers;",
            "RESET auto_explain.log_verbose;",
        ]
        for cmd in commands:
            await conn.execute(cmd)

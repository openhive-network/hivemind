"""Async DB adapter for hivemind API."""

import logging
from time import perf_counter as perf

from aiopg.sa import create_engine
import sqlalchemy
from sqlalchemy.engine.url import make_url

logging.getLogger('sqlalchemy.engine').setLevel(logging.INFO)
log = logging.getLogger(__name__)


class Db:
    """Wrapper for aiopg.sa db driver."""

    @classmethod
    async def create(cls, url):
        """Factory method."""
        instance = Db()
        await instance.init(url)
        return instance

    def __init__(self):
        self.db = None
        self._prep_sql = {}

    async def init(self, url):
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
        self.db = await create_engine(**dsn, maxsize=20, minsize=8, **conf.query)

    def close(self):
        """Close pool."""
        self.db.close()

    async def wait_closed(self):
        """Wait for releasing and closing all acquired connections."""
        await self.db.wait_closed()

    async def query_one(self, sql, **kwargs):
        """Perform a `SELECT 1*1`"""
        async with self.db.acquire() as conn:
            cur = await self._query(conn, sql, **kwargs)
            row = await cur.first()
        return row[0] if row else None

    async def query_all(self, sql, **kwargs):
        """Perform a `SELECT n*m`"""
        async with self.db.acquire() as conn:
            cur = await self._query(conn, sql, **kwargs)
            return await cur.fetchall()

    async def query(self, sql, **kwargs):
        """Perform a write query"""
        async with self.db.acquire() as conn:
            return await self._query(conn, sql, **kwargs)

    @staticmethod
    async def _query(conn, sql, **kwargs):
        """Send a query off to SQLAlchemy."""
        try:
            sql = str(sqlalchemy.text(sql)
                      .bindparams(**kwargs)
                      .compile(compile_kwargs={'literal_binds': True})
                      )
            before = perf()
            result = await conn.execute(sql)
            log.info(f'{perf() - before:.6f}s | {sql}')
            return result
        except Exception as e:
            log.warning(f'[SQL-ERR] {e.__class__.__name__} in query {sql}')
            raise e

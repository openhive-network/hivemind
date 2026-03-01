"""Database adapter using psycopg2 for direct PostgreSQL access."""

import logging
import re
from time import perf_counter as perf

import psycopg2
import psycopg2.extensions
import ujson
from psycopg2.extras import register_default_jsonb

from hive.db.autoexplain_controller import AutoExplainWrapper
from hive.utils.stats import Stats

log = logging.getLogger(__name__)

# Convert SA-style :param bindings to psycopg2 %(param)s syntax.
# Negative lookbehind avoids matching :: (PostgreSQL type casts) and :word_boundary.
_PARAM_RE = re.compile(r'(?<![:\w]):([a-zA-Z_]\w*)')


def _convert_named_params(sql):
    """Convert :param style bindings to %(param)s for psycopg2."""
    return _PARAM_RE.sub(r'%(\1)s', sql)


class Row:
    """Thin wrapper around a result row providing ._mapping for compatibility."""

    __slots__ = ('_data', '_columns')

    def __init__(self, data, columns):
        self._data = data
        self._columns = columns

    @property
    def _mapping(self):
        return dict(zip(self._columns, self._data))

    def __getitem__(self, index):
        return self._data[index]

    def __iter__(self):
        return iter(self._data)


class Db:
    """RDBMS adapter for hive. Handles connecting and querying."""

    _instance = None

    # maximum number of connections that is required so as to execute some tasks concurrently
    necessary_connections = 15
    max_connections = 1

    @classmethod
    def instance(cls):
        """Get the shared instance."""
        assert cls._instance, 'set_shared_instance was never called'
        return cls._instance

    @classmethod
    def set_shared_instance(cls, db):
        """Set the global/shared db instance. Do not use."""
        cls._instance = db

    @classmethod
    def set_max_connections(cls, db):
        """Remember maximum connections offered by postgres database."""
        assert db is not None, "Database has to be initialized"
        cls.max_connections = db.query_one("SELECT setting::int FROM pg_settings WHERE  name = 'max_connections'")
        if cls.necessary_connections > cls.max_connections:
            log.info(
                f"A database offers only {cls.max_connections} connections, but it's required {cls.necessary_connections} connections"
            )
        else:
            log.info(
                f"A database offers maximum connections: {cls.max_connections}. Required {cls.necessary_connections} connections."
            )

    def __init__(self, url, name, enable_autoexplain=False):
        """Initialize an instance.

        No work is performed here. Some modues might initialize an
        instance before config is loaded.
        """
        assert url, (
            '--database-url (or DATABASE_URL env) not specified; ' 'e.g. postgresql://user:pass@localhost:5432/hive'
        )
        self._url = str(url)
        self._trx_active = False
        self.name = name

        self._conn = psycopg2.connect(self._url, application_name=f'hivemind_{self.name}')
        self._conn.autocommit = True
        register_default_jsonb(self._conn, loads=ujson.loads)

        self.__autoexplain = None
        if enable_autoexplain:
            self.__autoexplain = AutoExplainWrapper(self)

    def clone(self, name):
        return Db(self._url, name, self.__autoexplain is not None)

    def impersonated_clone(self, name, role):
        role_url = psycopg2.extensions.make_dsn(self._url, user=role)
        return Db(role_url, name, self.__autoexplain is not None)

    def close(self):
        """Close connection."""
        try:
            if self._conn is not None and not self._conn.closed:
                log.info(f"Closing database connection: '{self.name}'")
                self._conn.close()
        except Exception as ex:
            log.exception(f"Error during connection closing: {ex}")
            raise ex

    def close_engine(self):
        """No-op, kept for backward compatibility."""
        pass

    def is_trx_active(self):
        """Check if a transaction is in progress."""
        return self._trx_active

    def explain(self):
        if self.__autoexplain:
            return self.__autoexplain
        return self

    def query(self, sql, **kwargs):
        """Perform a (*non-`SELECT`*) write query."""

        # if prepared tuple, unpack
        if isinstance(sql, tuple):
            assert not kwargs
            assert isinstance(sql[0], str)
            assert isinstance(sql[1], dict)
            sql, kwargs = sql

        # this method is reserved for anything but SELECT
        assert sql.strip()[0:6].strip() != 'SELECT', sql
        return self._query(sql, **kwargs)

    def query_no_return(self, sql, **kwargs):
        self._query(sql, **kwargs)

    def query_no_return_autocommit(self, sql):
        """Execute a query with autocommit enabled (outside any transaction).

        Required for commands like ALTER SYSTEM that cannot run inside a transaction block.
        Since we default to autocommit=True, this is a direct execute.
        """
        try:
            start = perf()
            with self._conn.cursor() as cur:
                cur.execute(sql)
            Stats.log_db(sql, perf() - start)
        except Exception as e:
            log.warning("[SQL-ERR] %s in autocommit query %s", e.__class__.__name__, sql)
            raise e

    def query_all(self, sql, **kwargs):
        """Perform a `SELECT n*m`"""
        return self._query(sql, **kwargs)

    def query_all_raw(self, sql, params=None):
        """Execute raw SQL with psycopg2 %s-style parameter binding.

        Use for queries with string-interpolated content that may contain
        colon-prefixed words (e.g., ':kingdom') which _convert_named_params
        would misinterpret as bind parameters.
        """
        try:
            start = perf()
            with self._conn.cursor() as cur:
                if params is not None:
                    cur.execute(sql, params)
                else:
                    cur.execute(sql)
                columns = [desc[0] for desc in cur.description] if cur.description else []
                rows = cur.fetchall()
            Stats.log_db(sql, perf() - start)
            return [Row(r, columns) for r in rows]
        except Exception as e:
            log.warning(f"[SQL-ERR] {e.__class__.__name__} in raw query")
            raise e

    def query_no_return_raw(self, sql, params=None):
        """Execute raw SQL with no result expected.

        Like query_all_raw but for statements that don't return rows (UPDATE, DELETE, etc.).
        """
        try:
            start = perf()
            with self._conn.cursor() as cur:
                if params is not None:
                    cur.execute(sql, params)
                else:
                    cur.execute(sql)
            Stats.log_db(sql, perf() - start)
        except Exception as e:
            log.warning(f"[SQL-ERR] {e.__class__.__name__} in raw query")
            raise e

    def query_row(self, sql, **kwargs):
        """Perform a `SELECT 1*m`"""
        rows = self._query(sql, **kwargs)
        return rows[0] if rows else None

    def query_col(self, sql, **kwargs):
        """Perform a `SELECT n*1`"""
        rows = self._query(sql, **kwargs)
        return [r[0] for r in rows]

    def query_one(self, sql, **kwargs):
        """Perform a `SELECT 1*1`"""
        rows = self._query(sql, **kwargs)
        if rows:
            return rows[0][0]
        return None

    def engine_name(self):
        """Get the name of the engine. Only postgresql is supported."""
        return 'postgresql'

    def batch_queries(self, queries, trx):
        """Process batches of prepared SQL tuples.

        If `trx` is true, the queries will be wrapped in a transaction.
        The format of queries is `[(sql, {params*}), ...]`
        """
        if trx:
            self.query("START TRANSACTION")
        for sql, params in queries:
            self.query(sql, **params)
        if trx:
            self.query("COMMIT")

    def _query(self, sql, **kwargs):
        """Execute a query using psycopg2."""
        if sql == 'START TRANSACTION':
            assert not self._trx_active
            self._trx_active = True
        elif sql == 'COMMIT' or sql == 'ROLLBACK':
            assert self._trx_active
            self._trx_active = False

        try:
            start = perf()
            converted = _convert_named_params(sql)
            with self._conn.cursor() as cur:
                cur.execute(converted, kwargs or None)
                columns = [desc[0] for desc in cur.description] if cur.description else []
                rows = cur.fetchall() if cur.description else []
            Stats.log_db(sql, perf() - start)
            return [Row(r, columns) for r in rows]
        except Exception as e:
            log.warning("[SQL-ERR] %s in query %s (%s)", e.__class__.__name__, sql, kwargs)
            raise e

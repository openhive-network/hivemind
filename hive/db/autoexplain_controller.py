import enum
import logging

log = logging.getLogger(__name__)


class PostgresClientLogSeverity(enum.Enum):
    debug5 = 1
    debug4 = 2
    debug3 = 3
    debug2 = 4
    debug1 = 5
    log = 6
    notice = 7
    warning = 8
    error = 9


class AutoExplainController:
    def __init__(self, _db):
        """
        Prepere the db for using autoexplain
        """
        self.__wrapped_db = _db
        self.__wrapped_db.query_no_return("LOAD 'auto_explain'")

    def __enter__(self):
        self.__wrapped_db.query_no_return("SET auto_explain.log_nested_statements=on")
        self.__wrapped_db.query_no_return("SET auto_explain.log_min_duration=0")
        self.__wrapped_db.query_no_return("SET auto_explain.log_analyze=on")
        self.__wrapped_db.query_no_return("SET auto_explain.log_buffers=on")
        self.__wrapped_db.query_no_return("SET auto_explain.log_verbose=on")

        self.__previous_psql_client_log_level = self.__wrapped_db.query_one("SHOW client_min_messages")
        if PostgresClientLogSeverity[self.__previous_psql_client_log_level].value > PostgresClientLogSeverity.log.value:
            self.__wrapped_db.query_no_return("SET client_min_messages=log")

        self.__previous_log_level = logging.getLogger('sqlalchemy.dialects').getEffectiveLevel()
        if self.__previous_log_level > getattr(logging, 'INFO'):
            logging.getLogger('sqlalchemy.dialects').setLevel(logging.INFO)

    def __exit__(self, exc_type, exc_value, traceback):
        self.__wrapped_db.query_no_return("SET auto_explain.log_nested_statements=off")
        self.__wrapped_db.query_no_return("SET auto_explain.log_min_duration=-1")
        self.__wrapped_db.query_no_return("SET auto_explain.log_analyze=off")
        self.__wrapped_db.query_no_return("SET auto_explain.log_buffers=off")
        self.__wrapped_db.query_no_return("SET auto_explain.log_verbose=off")

        if PostgresClientLogSeverity[self.__previous_psql_client_log_level].value > PostgresClientLogSeverity.log.value:
            self.__wrapped_db.query_no_return(f"SET client_min_messages={self.__previous_psql_client_log_level}")

        if self.__previous_log_level > getattr(logging, 'INFO'):
            logging.getLogger('sqlalchemy.dialects').setLevel(self.__previous_log_level)


class AutoExplainWrapper:
    def __init__(self, _db):
        self.__wrapped_db = _db

    def query(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            return self.__wrapped_db.query(sql, **kwargs)

    def query_no_return(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            self.__wrapped_db.query_no_return(sql, **kwargs)

    def query_all(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            return self.__wrapped_db.query_all(sql, **kwargs)

    def query_row(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            return self.__wrapped_db.query_row(sql, **kwargs)

    def query_col(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            return self.__wrapped_db.query_col(sql, **kwargs)

    def query_one(self, sql, **kwargs):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            return self.__wrapped_db.query_one(sql, **kwargs)

    def batch_queries(self, queries, trx):
        with AutoExplainController(self.__wrapped_db) as auto_explain:
            self.__wrapped_db.batch_queries(queries, trx)

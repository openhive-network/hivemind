import logging
from typing import Final

from sqlalchemy import text

from hive.conf import Conf
from hive.db.adapter import Db
from hive.indexer.block import OperationType, VirtualOperationType
from hive.signals import set_exception_thrown

log = logging.getLogger(__name__)

OPERATIONS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_operations4hivemind(:first, :last)"
BLOCKS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_blocks4hivemind(:first, :last)"

# Flat-row queries for massive sync (no ARRAY_AGG, no type wrapper, no hash/prev)
FLAT_OPS_QUERY: Final[str] = "SELECT * FROM hivemind_app.get_ops_for_hivemind(:first, :last)"
FLAT_BLOCKS_QUERY: Final[str] = "SELECT * FROM hivemind_app.get_block_dates_for_hivemind(:first, :last)"

# Extended query with extracted vote/effective_comment_vote fields as separate columns
FLAT_OPS_EXTENDED_QUERY: Final[str] = "SELECT * FROM hivemind_app.get_ops_for_hivemind_v2(:first, :last)"


class BlocksDataFromDbProvider:
    """Starts threads which takes operations for a range of blocks"""

    def __init__(self, sql_query: str, db: Db, strict: bool):
        self._db = db
        self._sql_query = sql_query
        self._strict = strict

    def get_data(self, lbound, ubound):
        try:
            stmt = text(self._sql_query).bindparams(first=lbound, last=ubound)
            data_rows = self._db.query_all(stmt, is_prepared=True)

            if not data_rows:
                msg = f'DATA ROWS ARE EMPTY! query: {stmt.compile(compile_kwargs={"literal_binds": True})}'
                if self._strict:
                    assert data_rows, msg
                else:
                    log.warning(msg)
            return data_rows
        except:
            set_exception_thrown()
            raise


class MassiveBlocksDataProviderHiveDb:
    _vop_types_dictionary = {}
    _op_types_dictionary = {}

    def __init__(self, conf: Conf, db_root: Db):
        self._conf = conf
        self._db = db_root

        self._operations_provider = BlocksDataFromDbProvider(sql_query=OPERATIONS_QUERY, db=db_root, strict=False)

        # Because HAF returns range of available blocks, it is impossible
        # to get empty results for asking for blocks
        self._blocks_data_provider = BlocksDataFromDbProvider(sql_query=BLOCKS_QUERY, db=db_root, strict=True)

        # Flat-row providers for massive sync
        self._flat_ops_provider = BlocksDataFromDbProvider(sql_query=FLAT_OPS_QUERY, db=db_root, strict=False)
        self._flat_blocks_provider = BlocksDataFromDbProvider(sql_query=FLAT_BLOCKS_QUERY, db=db_root, strict=True)

        # Extended provider with extracted vote fields
        self._flat_ops_extended_provider = BlocksDataFromDbProvider(
            sql_query=FLAT_OPS_EXTENDED_QUERY, db=db_root, strict=False
        )

        if not MassiveBlocksDataProviderHiveDb._vop_types_dictionary:
            virtual_operations_types_ids = self._db.query_all(
                "SELECT id, name FROM hafd.operation_types WHERE is_virtual  = true"
            )
            for id, name in virtual_operations_types_ids:
                MassiveBlocksDataProviderHiveDb._vop_types_dictionary[id] = VirtualOperationType.from_name(
                    name[len('hive::protocol::') :]
                )

        if not MassiveBlocksDataProviderHiveDb._op_types_dictionary:
            operations_types_ids = self._db.query_all(
                "SELECT id, name FROM hafd.operation_types WHERE is_virtual  = false"
            )
            for id, name in operations_types_ids:
                MassiveBlocksDataProviderHiveDb._op_types_dictionary[id] = OperationType.from_name(
                    name[len('hive::protocol::') :]
                )

    @staticmethod
    def _id_to_virtual_type(id_: int):
        if id_ in MassiveBlocksDataProviderHiveDb._vop_types_dictionary:
            return MassiveBlocksDataProviderHiveDb._vop_types_dictionary[id_]

    @staticmethod
    def _id_to_operation_type(id_: int):
        if id_ in MassiveBlocksDataProviderHiveDb._op_types_dictionary:
            return MassiveBlocksDataProviderHiveDb._op_types_dictionary[id_]

    @staticmethod
    def _operation_id_to_enum(id_: int):
        vop = MassiveBlocksDataProviderHiveDb._id_to_virtual_type(id_)
        if vop:
            return vop
        return MassiveBlocksDataProviderHiveDb._id_to_operation_type(id_)

    def get_blocks(self, lbound, ubound):
        return self._blocks_data_provider.get_data(lbound, ubound)

    def get_flat_ops(self, lbound, ubound):
        return self._flat_ops_provider.get_data(lbound, ubound)

    def get_flat_block_dates(self, lbound, ubound):
        return self._flat_blocks_provider.get_data(lbound, ubound)

    def get_flat_ops_extended(self, lbound, ubound):
        return self._flat_ops_extended_provider.get_data(lbound, ubound)

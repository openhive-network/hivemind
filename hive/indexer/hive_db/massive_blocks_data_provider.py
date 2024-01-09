from concurrent.futures import ThreadPoolExecutor
import logging
import queue
from typing import Final, List, Optional

from sqlalchemy import text

from hive.conf import Conf
from hive.db.adapter import Db
from hive.indexer.block import BlocksProviderBase, OperationType, VirtualOperationType
from hive.indexer.hive_db.block import BlockHiveDb
from hive.signals import can_continue_thread, set_exception_thrown
from hive.utils.stats import WaitingStatusManager as WSM

log = logging.getLogger(__name__)

OPERATIONS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_operations4hivemind(:first, :last)"
BLOCKS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_blocks4hivemind(:first, :last)"


class BlocksDataFromDbProvider:
    """Starts threads which takes operations for a range of blocks"""

    def __init__(
        self,
        sql_query: str,
        db: Db,
        blocks_per_request: int,
        external_thread_pool: Optional[ThreadPoolExecutor] = None,
    ):
        """
        external_thread_pool - thread pool controlled outside the class
        """

        assert blocks_per_request >= 1

        self._lbound = None
        self._ubound = None
        self._db = db
        self._thread_pool = external_thread_pool if external_thread_pool else ThreadPoolExecutor(1)
        self._blocks_per_request = blocks_per_request
        self._sql_query = sql_query

    def update_sync_block_range(self, lbound: int, ubound: int) -> None:
        self._lbound = lbound
        self._ubound = ubound

    def thread_body_get_data(self, queue_for_data):
        try:
            for block in range(self._lbound, self._ubound + 1, self._blocks_per_request):
                if not can_continue_thread():
                    break
                last = min([block + self._blocks_per_request - 1, self._ubound])

                stmt = text(self._sql_query).bindparams(first=block, last=last)

                data_rows = self._db.query_all(stmt, is_prepared=True)

                if not data_rows:
                    log.warning(f'DATA ROWS ARE EMPTY! query: {stmt.compile(compile_kwargs={"literal_binds": True})}')

                while can_continue_thread():
                    try:
                        queue_for_data.put(data_rows, True, 1)
                        break
                    except queue.Full:
                        continue
        except:
            set_exception_thrown()
            raise

    def start(self, queue_for_data):
        future = self._thread_pool.submit(self.thread_body_get_data, queue_for_data)
        return future


class MassiveBlocksDataProviderHiveDb(BlocksProviderBase):
    _vop_types_dictionary = {}
    _op_types_dictionary = {}

    class Databases:
        def __init__(self, db_root: Db, shared: bool = False):
            self._db_root = db_root
            self._db_operations = db_root.clone('MassiveBlocksProvider_OperationsData') if not shared else None
            self._db_blocks_data = db_root.clone('MassiveBlocksProvider_BlocksData') if not shared else None

            assert self._db_root

        def close_cloned_databases(self):
            self._db_operations.close()
            self._db_blocks_data.close()

        def get_root(self):
            return self._db_root

        def get_operations(self):
            return self._db_operations or self._db_root

        def get_blocks_data(self):
            return self._db_blocks_data or self._db_root

    def __init__(
        self,
        conf: Conf,
        databases: Databases,
        external_thread_pool: Optional[ThreadPoolExecutor] = None,
    ):
        BlocksProviderBase.__init__(self)

        self._conf = conf
        self._databases = databases
        self._db = databases.get_root()
        self._lbound = None
        self._ubound = None

        self._blocks_per_query = conf.get('max_batch')
        self._blocks_queue = queue.Queue(maxsize=self._blocks_queue_size)
        self._operations_queue = queue.Queue(maxsize=self._operations_queue_size)
        self._blocks_data_queue = queue.Queue(maxsize=self._blocks_data_queue_size)

        self._thread_pool = (
            external_thread_pool if external_thread_pool else MassiveBlocksDataProviderHiveDb.create_thread_pool()
        )

        self._operations_provider = BlocksDataFromDbProvider(
            sql_query=OPERATIONS_QUERY,
            db=databases.get_operations(),
            blocks_per_request=self._blocks_per_query,
            external_thread_pool=self._thread_pool,
        )
        self._blocks_data_provider = BlocksDataFromDbProvider(
            sql_query=BLOCKS_QUERY,
            db=databases.get_blocks_data(),
            blocks_per_request=self._blocks_per_query,
            external_thread_pool=self._thread_pool,
        )

        if not MassiveBlocksDataProviderHiveDb._vop_types_dictionary:
            virtual_operations_types_ids = self._db.query_all(
                "SELECT id, name FROM hive.operation_types WHERE is_virtual  = true"
            )
            for id, name in virtual_operations_types_ids:
                MassiveBlocksDataProviderHiveDb._vop_types_dictionary[id] = VirtualOperationType.from_name(
                    name[len('hive::protocol::') :]
                )

        if not MassiveBlocksDataProviderHiveDb._op_types_dictionary:
            operations_types_ids = self._db.query_all(
                "SELECT id, name FROM hive.operation_types WHERE is_virtual  = false"
            )
            for id, name in operations_types_ids:
                MassiveBlocksDataProviderHiveDb._op_types_dictionary[id] = OperationType.from_name(
                    name[len('hive::protocol::') :]
                )

    def update_sync_block_range(self, lbound: int, ubound: int) -> None:
        assert lbound <= ubound
        assert lbound >= 1

        self._lbound = lbound
        self._ubound = ubound
        self._operations_provider.update_sync_block_range(lbound, ubound)
        self._blocks_data_provider.update_sync_block_range(lbound, ubound)

    def close_databases(self):
        self._databases.close_cloned_databases()

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

    def _thread_get_block(self):
        try:
            while can_continue_thread():
                blocks_data = self._get_from_queue(self._blocks_data_queue, 1)  # batches of blocks  (lists)
                operations = self._get_from_queue(self._operations_queue, 1)

                if not can_continue_thread():
                    break

                assert len(blocks_data) == 1, "Always one element should be returned"
                assert len(operations) == 1, "Always one element should be returned"

                operations = operations[0]

                # MICKIEWICZ@NOTE najlepiej bezposrednio zapytać HAF-a o te dane w takim formacie, zamiast
                # pobierac to na kilku watkach a potem tutaj w pytonie żonglowac tymi dictami
                # jedynym powodem obecnej implementacji było zachowanie mozliwości pytania noda (get_block) i haf-a
                block_operation_idx = 0
                for block_data in blocks_data[0]:
                    new_block = BlockHiveDb(
                        block_data['num'],
                        block_data['date'],
                        block_data['hash'],
                        block_data['prev'],
                        None,
                        None,
                        MassiveBlocksDataProviderHiveDb._operation_id_to_enum,
                    )

                    for idx in range(block_operation_idx, len(operations)):
                        # find first the blocks' operation in the list
                        if operations[idx]['block_num'] == block_data['num']:
                            new_block = BlockHiveDb(
                                block_data['num'],
                                block_data['date'],
                                block_data['hash'],
                                block_data['prev'],
                                operations,
                                idx,
                                MassiveBlocksDataProviderHiveDb._operation_id_to_enum,
                            )
                            block_operation_idx = idx
                            break
                        if operations[block_operation_idx]['block_num'] > block_data['num']:
                            break

                    while can_continue_thread():
                        try:
                            self._blocks_queue.put(new_block, True, 1)
                            if block_data['num'] >= self._ubound:
                                return
                            break
                        except queue.Full:
                            # MICKIEWICZ@NOTICE moze lepiej poczekać dłuższą chwile aż hivemind zeżre troche z kolejek
                            continue
        except:
            set_exception_thrown()
            raise

    @staticmethod
    def create_thread_pool() -> ThreadPoolExecutor:
        """Creates initialzied thread pool with number of threads required by the provider.
        You can pass the thread pool to provider during its creation to controll its lifetime
        outside the provider"""

        return ThreadPoolExecutor(max_workers=MassiveBlocksDataProviderHiveDb.get_number_of_threads())

    @staticmethod
    def get_number_of_threads() -> int:
        return 3  # block data + operations + collect thread

    def start(self):
        return [
            self._operations_provider.start(queue_for_data=self._operations_queue),
            self._blocks_data_provider.start(queue_for_data=self._blocks_data_queue),
            self._thread_pool.submit(self._thread_get_block),
        ]  # futures

    def start_without_threading(self):
        self._blocks_data_provider.thread_body_get_data(queue_for_data=self._blocks_data_queue)
        self._operations_provider.thread_body_get_data(queue_for_data=self._operations_queue)
        self._thread_get_block()

    def get(self, number_of_blocks: int) -> List[BlockHiveDb]:
        """Returns blocks and vops data for next number_of_blocks"""
        log.info(f"blocks_data_queue.qsize: {self._blocks_data_queue.qsize()}")
        log.info(f"operations_queue.qsize: {self._operations_queue.qsize()}")
        log.info(f"blocks_queue.qsize: {self._blocks_queue.qsize()}")

        blocks = []
        wait_blocks_time = WSM.start()

        if self._blocks_queue.qsize() < number_of_blocks and can_continue_thread():
            log.info(f"Awaiting any blocks to process... {self._blocks_queue.qsize()}")

        if not self._blocks_queue.empty() or can_continue_thread():
            blocks = self._get_from_queue(self._blocks_queue, number_of_blocks)

        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        return blocks

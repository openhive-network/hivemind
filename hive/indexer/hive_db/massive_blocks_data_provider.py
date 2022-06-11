from concurrent.futures import ThreadPoolExecutor
import logging
import queue
from typing import Final, List, Optional

from sqlalchemy import text

from hive.conf import Conf
from hive.db.adapter import Db
from hive.indexer.block import BlocksProviderBase, OperationType, VirtualOperationType
from hive.indexer.hive_db.block import BlockHiveDb
from hive.indexer.mocking.mock_block import BlockMock, ExtendedByMockBlockAdapter
from hive.indexer.mocking.mock_block_provider import MockBlockProvider
from hive.indexer.mocking.mock_vops_provider import MockVopsProvider
from hive.signals import can_continue_thread, set_exception_thrown
from hive.utils.stats import WaitingStatusManager as WSM

log = logging.getLogger(__name__)

OPERATIONS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_operations4hivemind(:first, :last)"
BLOCKS_QUERY: Final[str] = "SELECT * FROM hivemind_app.enum_blocks4hivemind(:first, :last)"
NUMBER_OF_BLOCKS_QUERY: Final[str] = "SELECT num FROM hive.blocks ORDER BY num DESC LIMIT 1"


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
        self._last_block_num_in_db = None
        self.were_mocks_after_db_blocks = False

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

        if self._conf.get('test_max_block'):
            self._last_block_num_in_db = self._db.query_one(sql=NUMBER_OF_BLOCKS_QUERY)

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

    @staticmethod
    def _get_mocked_block(block_num, always_create):
        # normally it should create mocked block only when block mock or vops are added,
        # but there is a situation when we ask for mock blocks after the database head,
        # we need to alwyas return at least empty block otherwise live sync streamer
        # may hang in waiting for new blocks to start process already queued  block ( trailing block mechanism)
        # that is the reason why 'always_create' parameter was added
        # NOTE: it affects only situation when mocks are loaded, otherwiese mock provider methods
        # do not return block data
        vops_by_block_number = MockVopsProvider.get_mock_vops(block_num)

        block_data = MockBlockProvider.get_block_data(block_num, bool(vops_by_block_number) or always_create)
        if not block_data:
            return None

        return BlockMock(block_data, vops_by_block_number)

    def _get_mocks_after_db_blocks(self, first_mock_block_num):
        for block_proposition in range(first_mock_block_num, self._ubound + 1):
            if not can_continue_thread():
                return
            mocked_block = self._get_mocked_block(block_proposition, True)

            while can_continue_thread():
                try:
                    self._blocks_queue.put(mocked_block, True, 1)
                    break
                except queue.Full:
                    continue

    def _thread_get_block(self):
        try:
            # only mocked blocks are possible
            if self._conf.get('test_max_block') and self._lbound > self._last_block_num_in_db:
                log.info('ATTEMPTING TO GET MOCK BLOCKS AFTER DB BLOCKS')
                self.were_mocks_after_db_blocks = True
                self._get_mocks_after_db_blocks(self._lbound)
                return

            while can_continue_thread():
                blocks_data = self._get_from_queue(self._blocks_data_queue, 1)  # batches of blocks  (lists)
                operations = self._get_from_queue(self._operations_queue, 1)

                if not can_continue_thread():
                    break

                assert len(blocks_data) == 1, "Always one element should be returned"
                assert len(operations) == 1, "Always one element should be returned"

                operations = operations[0]

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

                    mocked_block = self._get_mocked_block(new_block.get_num(), False)
                    # live sync with mocks needs this, otherwise stream will wait almost forever for a block
                    MockBlockProvider.set_last_real_block_num_date(
                        new_block.get_num(), new_block.get_date(), new_block.get_hash()
                    )
                    if mocked_block:
                        new_block = ExtendedByMockBlockAdapter(new_block, mocked_block)
                        log.info(f'mocked block: {new_block.get_num()}')

                    while can_continue_thread():
                        try:
                            self._blocks_queue.put(new_block, True, 1)
                            if block_data['num'] >= self._ubound:
                                return
                            break
                        except queue.Full:
                            continue

                    # we reach last block in db, now only mocked blocks are possible
                    if self._conf.get('test_max_block') and new_block.get_num() >= self._last_block_num_in_db:
                        log.info('ATTEMPTING TO GET MOCK BLOCKS AFTER DB BLOCKS')
                        self.were_mocks_after_db_blocks = True
                        self._get_mocks_after_db_blocks(new_block.get_num() + 1)
                        return
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

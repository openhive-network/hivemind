from hive.utils.stats import WaitingStatusManager as WSM

from hive.indexer.block import VirtualOperationType, OperationType, BlocksProviderBase
from hive.indexer.hive_db.block import BlockHiveDb, OperationHiveDb
from hive.db.adapter import Db

from hive.indexer.mock_block_provider import MockBlockProvider
from hive.indexer.mock_vops_provider import MockVopsProvider
from hive.indexer.mock_block import ExtendedByMockBlockAdapter
from hive.indexer.hive_rpc.block_from_rest import BlockFromRpc

from concurrent.futures import ThreadPoolExecutor, as_completed

import asyncio
import logging
import queue

log = logging.getLogger(__name__)

operations_query = """
    SELECT * FROM enum_operations4hivemind( :first, :last )
   """

blocks_query = """SELECT * FROM enum_blocks4hivemind( :first, :last )"""

number_of_blocks_query = """SELECT num as num FROM hive_blocks ORDER BY num DESC LIMIT 1"""

class BlocksDataFromDbProvider:
    """Starts threads which takes operations for a range of blocks"""

    def __init__(self, sql_query, db, blocks_per_request, start_block, max_block, breaker, exception_reporter, external_thread_pool = None):
        """
            db - database
            start_block - block from which the processing starts
            max_block - last to get block's number
            breaker - callable object which returns true if processing must be continues
            exception_reporter - callable, invoke it when an exception occurs in a thread
            external_thread_pool - thread pool controlled outside the class
        """

        assert breaker
        assert db
        assert blocks_per_request >= 1
        assert sql_query

        self._breaker = breaker
        self._exception_reporter = exception_reporter
        self._start_block = start_block
        self._max_block = max_block # to inlude upperbound in results
        self._db = db
        if external_thread_pool:
            self._thread_pool = external_thread_pool
        else:
            self._thread_pool = ThreadPoolExecutor(1)
        self._blocks_per_request = blocks_per_request
        self._sql_query = sql_query



    def thread_body_get_data( self, queue_for_data ):
        try:
            for block in range ( self._start_block, self._max_block, self._blocks_per_request ):
                if not self._breaker():
                    break;

                data_rows = self._db.query_all( self._sql_query, first=block, last=min( [ block + self._blocks_per_request, self._max_block ] ))
                while self._breaker():
                    try:
                        queue_for_data.put( data_rows, True, 1 )
                        break
                    except queue.Full:
                        continue
        except:
            self._exception_reporter()
            raise

    def start(self, queue_for_data):
        future = self._thread_pool.submit( self.thread_body_get_data, queue_for_data  )
        return future



class MassiveBlocksDataProviderHiveDb(BlocksProviderBase):
    _vop_types_dictionary = {}
    _op_types_dictionary = {}

    class Databases:
        def __init__(self, conf):
            self._db_root = Db( conf.get('hived_database_url'), "MassiveBlocksProvider.Root", conf.get( 'log_explain_queries' )  )
            self._db_operations = Db( conf.get('hived_database_url'), "MassiveBlocksProvider.OperationsData", conf.get( 'log_explain_queries' ) )
            self._db_blocks_data = Db( conf.get('hived_database_url'), "MassiveBlocksProvider.BlocksData", conf.get( 'log_explain_queries' ) )

            assert self._db_root
            assert self._db_operations
            assert self._db_blocks_data

        def close(self):
            self._db_root.close()
            self._db_operations.close()
            self._db_blocks_data.close()

        def get_root(self):
            return self._db_root

        def get_operations(self):
            return self._db_operations

        def get_blocks_data(self):
            return self._db_blocks_data


    def __init__(
          self
        , databases
        , number_of_blocks_in_batch
        , lbound
        , ubound
        , breaker
        , exception_reporter
        , external_thread_pool = None ):
        """
            databases - object Databases with opened databases
            lbound - start blocks
            ubound - last block
        """
        assert lbound <= ubound
        assert lbound >= 0

        BlocksProviderBase.__init__(self, breaker, exception_reporter)

        self._db = databases.get_root()
        self._lbound = lbound
        self._ubound = ubound
        self._blocks_per_query = number_of_blocks_in_batch
        self._first_block_to_get =  lbound
        self._blocks_queue = queue.Queue( maxsize=self._blocks_queue_size )
        self._operations_queue = queue.Queue( maxsize=self._operations_queue_size )
        self._blocks_data_queue = queue.Queue( maxsize=self._blocks_data_queue_size )

        self._last_block_num_in_db = self._db.query_one( """SELECT num as num FROM hive_blocks ORDER BY num DESC LIMIT 1""" )
        assert self._last_block_num_in_db is not None

        if external_thread_pool:
            assert type(external_thread_pool) == ThreadPoolExecutor
            self._thread_pool = external_thread_pool
        else:
            self._thread_pool = MassiveBlocksDataProviderHiveDb.create_thread_pool()

        # read all blocks from db, rest of blocks ( ubound - self._last_block_num_in_db ) are supposed to be mocks
        self._operations_provider = BlocksDataFromDbProvider(
              operations_query
            , databases.get_operations()
            , self._blocks_per_query
            , self._lbound
            , self._last_block_num_in_db + 1 # ubound
            , breaker
            , exception_reporter
            , self._thread_pool
        )

        self._blocks_data_provider = BlocksDataFromDbProvider(
              blocks_query
            , databases.get_blocks_data()
            , self._blocks_per_query
            , self._lbound
            , self._last_block_num_in_db + 1 # ubound
            , breaker
            , exception_reporter
            , self._thread_pool
        )

        if not MassiveBlocksDataProviderHiveDb._vop_types_dictionary:
            virtual_operations_types_ids = self._db.query_all( "SELECT id, name FROM hive_operation_types WHERE is_virtual  = true" )
            for id, name in virtual_operations_types_ids:
                MassiveBlocksDataProviderHiveDb._vop_types_dictionary[ id ] = VirtualOperationType.from_name( name[len('hive::protocol::'):] )

        if not MassiveBlocksDataProviderHiveDb._op_types_dictionary:
            operations_types_ids = self._db.query_all( "SELECT id, name FROM hive_operation_types WHERE is_virtual  = false" )
            for id, name in operations_types_ids:
                MassiveBlocksDataProviderHiveDb._op_types_dictionary[ id ] = OperationType.from_name( name[len('hive::protocol::'):] )

    def _id_to_virtual_type(id):
        if id in MassiveBlocksDataProviderHiveDb._vop_types_dictionary:
            return MassiveBlocksDataProviderHiveDb._vop_types_dictionary[ id ]

    def _id_to_operation_type(id):
        if id in MassiveBlocksDataProviderHiveDb._op_types_dictionary:
            return MassiveBlocksDataProviderHiveDb._op_types_dictionary[ id ]

    def _operation_id_to_enum( id ):
        vop = MassiveBlocksDataProviderHiveDb._id_to_virtual_type( id )
        if vop:
            return vop
        return MassiveBlocksDataProviderHiveDb._id_to_operation_type( id )

    def _get_mocked_block( self, block_num, always_create ):
        # normally it should create mocked block only when block mock or vops are added,
        # but there is a situation when we ask for mock blocks after the database head,
        # we need to alwyas return at least empty block otherwise live sync streamer
        # may hang in waiting for new blocks to start process already queued  block ( trailing block mechanism)
        # that is the reason why 'always_create' parameter was added
        # NOTE: it affects only situation when mocks are loaded, otherwiese mock provider methods
        # do not return block data
        vops = {}
        MockVopsProvider.add_mock_vops(vops, block_num, block_num+1)

        block_mock = MockBlockProvider.get_block_data(block_num, bool(vops) or always_create )
        if not block_mock:
            return None

        if vops:
            vops = vops[block_num][ 'ops' ]
        return BlockFromRpc( block_mock, vops )

    def _get_mocks_after_db_blocks(self, first_mock_block_num):
        for block_proposition in range( first_mock_block_num, self._ubound ):
            if not self._breaker():
                return
            mocked_block = self._get_mocked_block( block_proposition, True )

            while self._breaker():
                try:
                    self._blocks_queue.put( mocked_block, True, 1 )
                    break
                except queue.Full:
                    continue

    def _thread_get_block(self):
        try:
            currently_received_block = 0

            # only mocked blocks are possible
            if self._lbound > self._last_block_num_in_db:
                self._get_mocks_after_db_blocks( self._lbound )
                return

            while self._breaker():
                blocks_data = self._get_from_queue(self._blocks_data_queue, 1)
                operations = self._get_from_queue(self._operations_queue, 1)


                if not self._breaker():
                    break

                assert len(blocks_data) == 1, "Always one element should be returned"
                assert len(operations) == 1, "Always one element should be returned"

                operations = operations[ 0 ]

                block_operation_idx = 0
                for block_data in blocks_data[0]:
                    new_block = BlockHiveDb(
                                      block_data[ 'num' ]
                                    , block_data[ 'date' ]
                                    , block_data[ 'hash' ]
                                    , block_data[ 'prev' ]
                                    , block_data[ 'tx_number' ]
                                    , block_data[ 'op_number' ]
                                    , None
                                    , None
                                    , MassiveBlocksDataProviderHiveDb._operation_id_to_enum
                                )

                    for idx in range( block_operation_idx, len(operations) ):
                        # find first the blocks' operation in the list
                        if operations[ idx ]['block_num'] == block_data[ 'num' ]:
                            new_block = BlockHiveDb(
                                  block_data[ 'num' ]
                                , block_data[ 'date' ]
                                , block_data[ 'hash' ]
                                , block_data[ 'prev' ]
                                , block_data[ 'tx_number' ]
                                , block_data[ 'op_number' ]
                                , operations
                                , idx
                                , MassiveBlocksDataProviderHiveDb._operation_id_to_enum
                                 )
                            block_operation_idx = idx
                            break;
                        if operations[ block_operation_idx ]['block_num'] > block_data[ 'num' ]:
                            break;

                    mocked_block = self._get_mocked_block( new_block.get_num(), False )
                    # live sync with mocks needs this, otherwise stream will wait almost forever for a block
                    MockBlockProvider.set_last_real_block_num_date( new_block.get_num(), new_block.get_date(), new_block.get_hash() )
                    if mocked_block:
                        new_block = ExtendedByMockBlockAdapter( new_block, mocked_block )

                    while self._breaker():
                        try:
                            self._blocks_queue.put( new_block, True, 1 )
                            currently_received_block += 1
                            if currently_received_block >= (self._ubound - 1):
                                return
                            break
                        except queue.Full:
                            continue

                    # we reach last block in db, now only mocked blocks are possible
                    if new_block.get_num() >= self._last_block_num_in_db:
                        self._get_mocks_after_db_blocks( new_block.get_num() + 1 )
                        return
        except:
            self._exception_reporter()
            raise

    def create_thread_pool():
        """Creates initialzied thread pool with number of threads required by the provider.
        You can pass the thread pool to provider during its creation to controll its lifetime
        outside the provider"""

        return ThreadPoolExecutor( max_workers = MassiveBlocksDataProviderHiveDb.get_number_of_threads() )

    def get_number_of_threads():
        return 3  # block data + operations + collect thread

    def start(self):
        futures = []
        futures.append( self._operations_provider.start( self._operations_queue ) )
        futures.append( self._blocks_data_provider.start( self._blocks_data_queue ) )

        futures.append( self._thread_pool.submit( self._thread_get_block ) )
        return futures

    def get( self, number_of_blocks ):
        """Returns blocks and vops data for next number_of_blocks"""
        blocks = []
        wait_blocks_time = WSM.start()

        if self._blocks_queue.qsize() < number_of_blocks and self._breaker():
                 log.info("Awaiting any blocks to process... {}".format(self._blocks_queue.qsize()))

        if not self._blocks_queue.empty() or self._breaker():
            blocks = self._get_from_queue( self._blocks_queue, number_of_blocks )

        WSM.wait_stat('block_consumer_block', WSM.stop(wait_blocks_time))

        return blocks

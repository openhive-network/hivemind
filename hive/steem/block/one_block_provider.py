from hive.indexer.hive_rpc.massive_blocks_data_provider_hive_rpc import MassiveBlocksDataProviderHiveRpc
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.indexer.block import Block


from abc import ABC, abstractmethod
import logging

log = logging.getLogger(__name__)

class OneBlockProviderBase(ABC):

    def __init__(self, conf, node, breaker, exception_reporter, thread_pool ):
        self._conf = conf
        self._node = node
        self._breaker = breaker
        self._exception_reporter = exception_reporter
        self._thread_pool = thread_pool

    def _get_block_from_provider(self, blocks_provider, block_num):
        futures = blocks_provider.start()
        for future in futures:
            exception = future.exception()
            if exception:
                raise exception

        blocks = blocks_provider.get( 1 )
        if len(blocks):
            return blocks[ 0 ]
        return None

    @abstractmethod
    def get_block( self, block_num ):
        pass

class OneBlockProviderFromHivedDb(OneBlockProviderBase):

    def __init__(self, conf, node, breaker, exception_reporter, databases, thread_pool  ):
        assert databases

        OneBlockProviderBase.__init__(self, conf, node, breaker, exception_reporter, thread_pool )
        self._databases_for_massive_sync = databases


    def get_block( self, block_num ):
        blocks_provider = MassiveBlocksDataProviderHiveDb(
              self._databases_for_massive_sync
            , 1
            , block_num + 1
            , self._breaker
            , self._exception_reporter
            , self._thread_pool
        )

        return self._get_block_from_provider(blocks_provider, block_num)

class OneBlockProviderFromNode(OneBlockProviderBase):

    def __init__(self, conf, node, breaker, exception_reporter, thread_pool ):
        OneBlockProviderBase.__init__(self, conf, node, breaker, exception_reporter, thread_pool )

    def get_block( self, block_num ):
        blocks_provider = MassiveBlocksDataProviderHiveRpc(
              self._conf
            , self._node # node client
            , blocks_get_threads = 1
            , vops_get_threads = 1
            , number_of_blocks_data_in_one_batch = 1
            , ubound = block_num + 1
            , breaker = self._breaker
            , exception_reporter = self._exception_reporter
            , external_thread_pool = self._thread_pool
        )
        return self._get_block_from_provider(blocks_provider, block_num)

class OneBlockProviderFactory:
    def __init__( self, conf, node, breaker, exception_reporter ):
        self._conf = conf
        self._node = node
        self._breaker = breaker
        self._exception_reporter = exception_reporter
        self._databases_for_massive_sync = None
        self._thread_pool = None

    def __enter__(self):
        if ( self._conf.get('hived_database_url') ):
            self._databases_for_massive_sync = MassiveBlocksDataProviderHiveDb.Databases( self._conf )
            self._thread_pool = MassiveBlocksDataProviderHiveDb.create_thread_pool()
            return OneBlockProviderFromHivedDb( self._conf, self._node, self._breaker, self._exception_reporter, self._databases_for_massive_sync, self._thread_pool )

        self._thread_pool = MassiveBlocksDataProviderHiveRpc.create_thread_pool( 1, 1 )
        return OneBlockProviderFromNode( self._conf, self._node, self._breaker, self._exception_reporter, self._thread_pool )

    def __exit__(self, exc_type, exc_value, traceback):
        if self._databases_for_massive_sync:
            self._databases_for_massive_sync.close()

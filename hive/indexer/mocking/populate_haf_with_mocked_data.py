import logging
import sys
from typing import List
from typing import Optional
from typing import Sequence

import configargparse

from hive.db.adapter import Db
from hive.indexer.mocking.mock_block import BlockMock
from hive.indexer.mocking.mock_block import BlockMockAfterDb
from hive.indexer.mocking.mock_block_provider import MockBlockProvider
from hive.indexer.mocking.mock_vops_provider import MockVopsProvider

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)


def init_argparse(args: Sequence[str]) -> configargparse.Namespace:
    parser = configargparse.ArgumentParser(formatter_class=configargparse.RawTextHelpFormatter)

    add = parser.add_argument
    add('--database-url', env_var='DATABASE_URL', required=True, help='database connection url')
    add(
        '-l',
        '--last-block-to-process',
        type=int,
        env_var='LAST_BLOCK_TO_PROCESS',
        help='Could be lower than value in mock data',
    )
    add(
        '--mock-block-data-paths',
        type=str,
        nargs='+',
        env_var='MOCK_BLOCK_DATA_PATH',
        help='(debug/testing) load additional data from block data file',
    )
    add(
        '--mock-vops-data-paths',
        type=str,
        nargs='+',
        env_var='MOCK_VOPS_DATA_PATH',
        help='(debug/testing) load additional data from virtual operations data file',
    )

    return parser.parse_args(args)


def load_mock_data(mock_block_data_paths: Optional[List[str]] = None, mock_vops_data_paths: Optional[List[str]] = None):
    log.info('Loading mock data')
    mock_block_data_paths = [] if not mock_block_data_paths else mock_block_data_paths
    mock_vops_data_paths = [] if not mock_vops_data_paths else mock_vops_data_paths

    for path in mock_block_data_paths:
        MockBlockProvider.load_block_data(path)

    for path in mock_vops_data_paths:
        MockVopsProvider.load_block_data(path)


def create_mocked_blocks_after_haf_db_blocks(lbound: int, ubound: int):
    log.info(f'Creating mocked blocks in db from {lbound} to {ubound}')
    for block_number in range(lbound, ubound + 1):
        block_data = MockBlockProvider.make_empty_block(block_num=block_number)
        block = BlockMockAfterDb(
            block_number=block_number,
            hash=block_data['block_id'],
            previous_hash=block_data['previous'],
            created_at=block_data['timestamp'],
        )
        block.push()


def main():
    args = init_argparse(sys.argv[1:])

    log.info(f'Setting up the database connection using URL {args.database_url}')
    db = Db(url=args.database_url, name='mocker')
    Db.set_shared_instance(db)

    load_mock_data(mock_block_data_paths=args.mock_block_data_paths, mock_vops_data_paths=args.mock_vops_data_paths)

    block_data = MockBlockProvider.block_data

    log.info('Processing block data')
    blocks = []
    for block_number, data in block_data.items():

        if args.last_block_to_process and block_number > args.last_block_to_process:
            continue

        vops = MockVopsProvider.get_mock_vops(block_number=block_number)
        block = BlockMock(block_number=block_number, block_data=data, virtual_ops=vops)
        blocks.append(block)

    log.info('Sorting block data')
    blocks.sort(key=lambda b: b.block_number)

    last_block_in_db = db.query_row("SELECT * FROM hafd.blocks ORDER BY num DESC LIMIT 1")
    log.info(f'Last block in db: {last_block_in_db["num"]}')

    last_block_num_to_mock = blocks[-1].block_number
    log.info(f'Last block to mock: {last_block_num_to_mock}')

    if last_block_num_to_mock > last_block_in_db['num']:
        MockBlockProvider.set_last_real_block_num_date(
            block_num=last_block_in_db['num'],
            block_date=last_block_in_db['created_at'],
            block_id=last_block_in_db['hash'],
        )

        create_mocked_blocks_after_haf_db_blocks(lbound=last_block_in_db['num'] + 1, ubound=last_block_num_to_mock)
        Db.instance().query_no_return(f'SELECT hive.set_irreversible({last_block_num_to_mock})')
        log.info(f'Irreversible block set to {last_block_num_to_mock}')

    for block in blocks:
        log.info(f'####################################################### Block number: {block.block_number} STARTING')

        for transaction in block.get_next_transaction():
            transaction.push()

            for operation in transaction.get_next_operation():
                operation.push()

        for virtual_operation in block.get_next_virtual_operation():
            virtual_operation.push()

        log.info(f'####################################################### Block number: {block.block_number} FINISHED')

    db.close()


if __name__ == '__main__':
    main()

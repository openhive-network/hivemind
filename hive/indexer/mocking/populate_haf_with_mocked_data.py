import logging
import sys
from typing import List
from typing import Optional
from typing import Sequence

import configargparse

from hive.db.adapter import Db
from hive.indexer.mocking.mock_block import BlockMock
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
    mock_block_data_paths = [] if not mock_block_data_paths else mock_block_data_paths
    mock_vops_data_paths = [] if not mock_vops_data_paths else mock_vops_data_paths

    for path in mock_block_data_paths:
        MockBlockProvider.load_block_data(path)

    for path in mock_vops_data_paths:
        MockVopsProvider.load_block_data(path)


def main():
    args = init_argparse(sys.argv[1:])

    db = Db(url=args.database_url, name='mocker')
    Db.set_shared_instance(db)

    load_mock_data(mock_block_data_paths=args.mock_block_data_paths, mock_vops_data_paths=args.mock_vops_data_paths)

    block_data = MockBlockProvider.block_data

    blocks = []
    for block_number, data in block_data.items():

        if args.last_block_to_process and block_number > args.last_block_to_process:
            continue

        vops = MockVopsProvider.get_mock_vops(block_number=block_number)
        block = BlockMock(block_number=block_number, block_data=data, virtual_ops=vops)
        blocks.append(block)

    for block in sorted(blocks, key=lambda b: b.block_number):
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

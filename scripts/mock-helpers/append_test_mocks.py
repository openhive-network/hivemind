import logging
import json
import os
import sys
from typing import Sequence
import configargparse
from hive.db.adapter import Db
from hive.indexer.mocking import populate_haf_with_mocked_data

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)

def init_argparse(args: Sequence[str]) -> configargparse.Namespace:
    parser = configargparse.ArgumentParser(
        description="Helper script to automatically change the block number in the provided mock file via --mock-block-data-paths to allow you to append extra ops and test indexing functions granularly without having to resync an entire db / updating your mocks files"
                    "\n Example usage: python append_test_mocks.py --mock-block-data-paths=/home/howo/hivemind/scripts/mock-helpers/ops --database-url postgresql://postgres:root@localhost:5432/haf_block_log --mock-vops-data-paths=/home/howo/hivemind/scripts/mock-helpers/vops",
        formatter_class=configargparse.RawTextHelpFormatter
    )

    add = parser.add_argument
    add('--database-url', env_var='DATABASE_URL', type=str, required=True, help='database connection url')
    add('--mock-block-data-paths', type=str, required=True, help='location of the mock path containing mocked_dev_ops.json')
    add('--mock-vops-data-paths', type=str, required=True, help='location of the vops mock path containing mocked_dev_ops.json')

    return parser.parse_args(args)

def main():
    args = init_argparse(sys.argv[1:])

    log.info(f'Setting up the database connection using URL {args.database_url}')
    db = Db(url=args.database_url, name='mocker')
    Db.set_shared_instance(db)

    last_block_in_hivemind = db.query_row("SELECT * FROM hivemind_app.hive_state LIMIT 1")
    log.info(f'Last block in hivemind: {last_block_in_hivemind["last_imported_block_num"]}')

    new_block = int(last_block_in_hivemind["last_imported_block_num"]) + 1
    mock_file_ops = os.path.join(args.mock_block_data_paths, "mocked_dev_ops.json")
    mock_file_vops = os.path.join(args.mock_vops_data_paths, "mocked_dev_vops.json")

    try:
        with open(mock_file_ops, 'r') as file:
            data = json.load(file)
            # Assuming there is only one key at the top level
            old_key = next(iter(data))
            data[new_block] = data.pop(old_key)
        with open(mock_file_ops, 'w') as file:
            json.dump(data, file, indent=4)

        with open(mock_file_vops, 'r') as file:
            data = json.load(file)
            # Assuming there is only one key at the top level
            old_key = next(iter(data))
            data[new_block] = data.pop(old_key)
        with open(mock_file_vops, 'w') as file:
            json.dump(data, file, indent=4)

        log.info(f"Mocks updated with new block number: {new_block}")
        log.info(f"Populating mocks")
        populate_haf_with_mocked_data.main()

    except Exception as e:
        log.error(f"An error occurred: {e}")

if __name__ == "__main__":
    main()

import logging
import json
import os
import sys
from typing import Sequence
import configargparse
from hive.db.adapter import Db
import subprocess

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)

def init_argparse(args: Sequence[str]) -> configargparse.Namespace:
    parser = configargparse.ArgumentParser(formatter_class=configargparse.RawTextHelpFormatter)

    add = parser.add_argument
    add('--database-url', env_var='DATABASE_URL', type=str, required=True, help='database connection url')
    add('--mock-file-path', type=str, required=True, help='location of the mock file to update')
    add('--populate-mocks-script-path', type=str, required=True, help='location of the populate mocks script')

    return parser.parse_args(args)

def main():
    args = init_argparse(sys.argv[1:])

    log.info(f'Setting up the database connection using URL {args.database_url}')
    db = Db(url=args.database_url, name='mocker')
    Db.set_shared_instance(db)

    last_block_in_hivemind = db.query_row("SELECT * FROM hivemind_app.hive_state LIMIT 1")
    log.info(f'Last block in hivemind: {last_block_in_hivemind["last_imported_block_num"]}')

    new_block = int(last_block_in_hivemind["last_imported_block_num"]) + 1

    try:
        with open(args.mock_file_path, 'r') as file:
            data = json.load(file)

        # Assuming there is only one key at the top level
        old_key = next(iter(data))
        data[new_block] = data.pop(old_key)

        with open(args.mock_file_path, 'w') as file:
            json.dump(data, file, indent=4)
        log.info(f"Mocks updated with new block number: {new_block}")
        mock_data_dir = os.path.dirname(args.mock_file_path)
        log.info(f"Populate mocks by calling python3 {args.populate_mocks_script_path} --database-url {args.database_url} --mock-block-data-paths {mock_data_dir}")

    except Exception as e:
        log.error(f"An error occurred: {e}")



if __name__ == "__main__":
    main()

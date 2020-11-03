#!/usr/bin/python3

from json import dumps
from hive.steem.client import SteemClient

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()

    parser.add_argument("hivemind_address", type=str, help="Address of hivemind instance")
    parser.add_argument("from_block", type=int, help="Scan from block")
    parser.add_argument("to_block", type=int, help="Scan to block")
    parser.add_argument("output_file", type=str, help="Prepared blocks will be saved in this file")
    parser.add_argument("operations", type=str, nargs='+', help="Save selected operations")
    parser.add_argument("--dump-ops-only", type=bool, default=False, help="Dump only selected ops without block data")

    args = parser.parse_args()

    client = SteemClient({"default":args.hivemind_address})
    from_block = args.from_block
    with open(args.output_file, "w") as output_file:
        if not args.dump_ops_only:
            output_file.write("{\n")
        while from_block < args.to_block:
            to_block = from_block + 1000
            if to_block >= args.to_block:
                to_block = args.to_block + 1
            print("Processing range from: ", from_block, " to: ", to_block)
            blocks = client.get_blocks_range(from_block, to_block)
            for block in blocks:
                block_num = int(block['block_id'][:8], base=16)
                block_data = dict(block)
                for idx in range(len(block_data['transactions'])):
                    block_data['transactions'][idx]['operations'] = [op for op in block_data['transactions'][idx]['operations'] if op['type'] in args.operations]
                    if args.dump_ops_only and block_data['transactions'][idx]['operations']:
                        output_file.write("{}\n".format(dumps(block_data['transactions'][idx]['operations'])))
                if not args.dump_ops_only:
                    output_file.write('"{}":{},\n'.format(block_num, dumps(block_data)))
            from_block = to_block
        if not args.dump_ops_only:
            output_file.write("}\n")

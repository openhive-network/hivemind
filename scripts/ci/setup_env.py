#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Tool for Gitlab runner to read environment from project variable
and setup bash environment.
When running on Gitlab CI you can  do this:
```
eval "$(cat $MY_ENV_VARIABLE | ./scripts/ci/setup_env.py)"
echo "RUNNER_ID is $RUNNER_ID"
```
In bash you can do this:
```
eval "$(cat ./.tmp/env.yaml | ./scripts/ci/setup_env.py)"
echo "RUNNER_ID is $RUNNER_ID"
```
"""

import logging
import sys
import argparse
import yaml

FORMAT = '# %(asctime)s - %(name)s - %(levelname)s - %(message)s '
logging.basicConfig(format=FORMAT)
logger = logging.getLogger(__name__)


def output(message, outfile, end='\n'):
    """Print data to outfile"""
    print(message, file=outfile, end=end)


def read(infile):
    """Read data from infile"""
    if hasattr(infile, 'read'):
        # data = json.loads(infile.read())
        data = yaml.safe_load(infile.read())
    else:
        # data = json.loads(infile)
        data = yaml.safe_load(infile)
    return data


def setup_env(current_runner_id, hive_sync_runner_id, infile, outfile, end, **kwargs):
    """
    Resolve and output environment for bash in pending CI job.
    Assumption: all jobs in pipeline must use the same database.
    We need to point current runner to the database used by runner,
    that did hive sync (first stage in pipeline).
    """

    logger.debug('current_runner_id: %s', current_runner_id)
    logger.debug('hive_sync_runner_id: %s', hive_sync_runner_id)

    data = read(infile)
    logger.debug('data: %s', data)

    current_runner = data['runners'][str(current_runner_id)]
    if hive_sync_runner_id == 0:
        hive_sync_runner = current_runner
    else:
        hive_sync_runner = data['runners'][str(hive_sync_runner_id)]

    if hive_sync_runner_id == 0:
        # Do nothing, obviously. Current runner does hive sync itself.
        logger.debug('case 1')
        runner = current_runner
    elif current_runner_id == hive_sync_runner_id:
        # Do nothing, obviously. Current runner is the same, as runner
        # that did hive sync.
        logger.debug('case 2')
        runner = current_runner
    else:
        if current_runner['host'] == hive_sync_runner['host']:
            # We assume that all executors on the same machine
            # use the same postgres server with the same credentials
            # and unix socket connection configuration. So do nothing.
            logger.debug('case 3')
            runner = current_runner
        else:
            # Take postgres stuff from runner that did hive sync,
            # but point current runner to postgres on the host of runner
            # that did hive sync (exposed on network, we assume).
            logger.debug('case 4')
            runner = {}
            for key, value in current_runner.items():
                if key.startswith('postgres'):
                    if key == 'postgres_host':
                        runner[key] = hive_sync_runner['host']
                    if key == 'postgres_port':  # to be eliminated when CI will be only at psql12
                        runner[key] = 25432
                    else:
                        runner[key] = hive_sync_runner[key]
                else:
                    runner[key] = value

    for key in runner:
        if key == 'postgres_host':  # to be eliminated when CI will be only at psql12
            runner[key] = 'localhost'
        if key == 'postgres_port':  # to be eliminated when CI will be only at psql12
            runner[key] = 25432

        output(
            f'export RUNNER_{key.upper()}="{str(runner[key])}"',
            outfile,
            end,
        )

    for key in data['common']:
        output(
            f"export RUNNER_{key.upper()}=\"{str(data['common'][key])}\"",
            outfile,
            end,
        )


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        'infile', type=argparse.FileType('r'), nargs='?', default=sys.stdin, help='Input file or pipe via STDIN'
    )
    parser.add_argument(
        '-o', '--outfile', type=argparse.FileType('w'), default=sys.stdout, help='Output file, STDOUT if not set'
    )
    parser.add_argument("-e", "--end", dest='end', default='\n', help='String at the end of line in output')
    parser.add_argument(
        "-s",
        "--hive-sync-runner-id",
        required=True,
        type=int,
        help='Id of runner which did hive sync, 0 when current runner does hive sync actually',
    )
    parser.add_argument("-c", "--current-runner-id", required=True, type=int, help='Id of current runner')
    parser.add_argument(
        '--log-level',
        default='INFO',
        dest='log_level',
        choices=['debug', 'info', 'warning', 'error'],
        help='Log level (string)',
    )

    result = parser.parse_args()

    # configure logger and print config
    root = logging.getLogger()
    root.setLevel(result.log_level.upper())

    return result


def main():
    """Main dispatcher function"""
    flags = parse_args()
    setup_env(**vars(flags))


if __name__ == '__main__':
    main()

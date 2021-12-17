from __future__ import annotations

import argparse
import datetime
from hashlib import sha256
from pathlib import Path
import socket

from db_adapter import Db


def benchmark_description(args: argparse.Namespace, ) -> dict[str, str]:
    return {'description': args.desc,
            'execution_environment_description': args.exec_env_desc,
            'timestamp': datetime.datetime.now().strftime('%Y/%m/%d, %H:%M:%S'),
            'server_name': args.server_name,
            'app_version': args.app_version,
            'testsuite_version': args.testsuite_version,
            'runner': socket.gethostname(),
            }


def get_lines_from_log_file(file_path: Path) -> list[str]:
    with open(file_path, 'r') as file:
        return file.readlines()


def get_text_from_log_file(file_path: Path) -> str:
    with open(file_path, 'r') as file:
        return file.read()


def calculate_hash(*args) -> str:
    return sha256(str(args).encode('utf-8')).hexdigest()


def retrieve_cols_and_params(cols_args: dict[str, str]) -> tuple[str, str]:
    """
    Parse dict of cols_args into a two separated strings formats that are needed when
    building a SQL for '_query' method of db_adapter.
    """

    fields = list(cols_args.keys())
    cols = ', '.join([k for k in fields])
    params = ', '.join([f':{k}' for k in fields])
    return cols, params


async def insert_row(db: Db, table: str, cols_args: dict) -> None:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params});'
    await db.query(sql, **cols_args)


async def insert_row_with_returning(db: Db, table: str, cols_args: dict, additional: str = '') -> int:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params}) {additional};'
    return await db.query_one(sql, **cols_args)

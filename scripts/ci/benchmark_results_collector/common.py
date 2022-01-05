from __future__ import annotations

import dataclasses
from hashlib import sha256
import logging
from pathlib import Path

from db_adapter import Db

log = logging.getLogger(__name__)


@dataclasses.dataclass
class MappedDbData:
    caller: str
    method: str
    params: str
    value: int
    unit: str
    id: int = dataclasses.field(init=False)
    hash: str = dataclasses.field(init=False)

    def __post_init__(self):
        self.id = 1  # set when function `distinguish_objects_having_same_hash()` is called
        self.hash = calculate_hash(self.caller, self.method, self.params)

    async def insert_into_testcase_table(self, db: Db) -> None:
        await insert_row(db,
                         table='public.testcase',
                         cols_args={'hash': self.hash,
                                    'caller': self.caller,
                                    'method': self.method,
                                    'params': self.params,
                                    },
                         additional=' ON CONFLICT (hash) DO NOTHING;',
                         )

    async def insert_into_benchmark_values_table(self, db: Db, benchmark_id: int) -> None:
        await insert_row(db,
                         table='public.benchmark_values',
                         cols_args={'benchmark_description_id': benchmark_id,
                                    'testcase_hash': self.hash,
                                    'occurrence_number': self.id,
                                    'value': self.value,
                                    'unit': self.unit,
                                    })

    async def insert(self, db: Db, benchmark_id: int) -> None:
        await self.insert_into_testcase_table(db)
        await self.insert_into_benchmark_values_table(db, benchmark_id)


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


async def insert_row(db: Db, table: str, cols_args: dict, additional: str = '') -> None:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params}) {additional};'
    await db.query(sql, **cols_args)


async def insert_row_with_returning(db: Db, table: str, cols_args: dict, additional: str = '') -> int:
    cols, params = retrieve_cols_and_params(cols_args)
    sql = f'INSERT INTO {table} ({cols}) VALUES ({params}) {additional};'
    return await db.query_one(sql, **cols_args)


def distinguish_objects_having_same_hash(objects: list) -> None:
    same_by_hash = {}

    for obj in objects:
        if (hash := obj.hash) not in same_by_hash:
            same_by_hash[hash] = [obj]
        else:
            same_by_hash[hash].append(obj)

    for lst in same_by_hash.values():
        id = 1
        for parsed in lst:
            parsed.id = id
            id += 1

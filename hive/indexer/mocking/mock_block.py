import datetime
import hashlib
import logging
from abc import abstractmethod
from collections.abc import Iterator
from typing import Optional, Union

import ujson as json

from hive.db.adapter import Db
from hive.indexer.block import OperationType, VirtualOperationType

log = logging.getLogger(__name__)


class AccountMock:
    account_id: Optional[int] = None

    def __init__(self, block_number: int, name: str):
        self._block_number = block_number
        self._name = name

        if self.__class__.account_id is None:
            last_account_id = Db.instance().query_one(sql='SELECT id from hafd.accounts ORDER BY id DESC LIMIT 1;')
            log.info(f'Last account id stored in HAf database is: {last_account_id}')
            self.__class__.account_id = last_account_id

    @property
    def block_number(self) -> int:
        return self._block_number

    @property
    def name(self) -> str:
        return self._name

    def push(self) -> None:
        sql = """
INSERT INTO
    hafd.accounts (id, name, block_num)
VALUES
    (:id, :name, :block_num);
"""

        self.__class__.account_id += 1

        log.info(f'Attempting to push mocked ACCOUNT with name: {self.name}')

        Db.instance().query(
            sql=sql,
            id=self.__class__.account_id,
            name=self.name,
            block_num=self.block_number,
        )

        log.info('ACCOUNT pushed successfully!')


class OperationBase:
    operation_id: Optional[int] = None
    pos_in_block: Optional[int] = 1

    def __init__(self, block_number: int, body: dict):
        self._block_number = block_number
        self._body = body

        if OperationBase.operation_id is None:
            last_operation_id = Db.instance().query_one(sql='SELECT id from hafd.operations ORDER BY id DESC LIMIT 1;')
            log.info(f'Last operation id stored in HAf database is: {last_operation_id}')
            OperationBase.operation_id = last_operation_id

    @property
    @abstractmethod
    def type(self) -> Optional[Union[OperationType, VirtualOperationType]]:
        raise NotImplementedError

    @property
    def block_number(self) -> int:
        return self._block_number

    @property
    def body(self) -> dict:
        return self._body

    _custom_json_seq_synced = False

    def _resolve_custom_json_type_id(self):
        """For custom_json operations, resolve or insert the custom_json_type_id."""
        if self.type != OperationType.CUSTOM_JSON:
            return None
        cj_id = self.body.get('value', {}).get('id')
        if not cj_id:
            return None
        # Try to find existing type first (populated by hived during replay)
        type_id = Db.instance().query_one(
            sql="SELECT id FROM hafd.custom_json_types WHERE custom_json_id = :cj_id",
            cj_id=cj_id,
        )
        if type_id is not None:
            return type_id
        # Sync the identity sequence once before first insert — hived uses
        # OVERRIDING SYSTEM VALUE which doesn't advance the sequence
        if not OperationBase._custom_json_seq_synced:
            Db.instance().query_one(
                sql="SELECT setval(pg_get_serial_sequence('hafd.custom_json_types', 'id'), GREATEST(COALESCE(MAX(id), 0), 1)) FROM hafd.custom_json_types"
            )
            OperationBase._custom_json_seq_synced = True
        # Insert new type for mock-only custom_json ids not seen during replay
        return Db.instance().query_one(
            sql="""
                INSERT INTO hafd.custom_json_types(custom_json_id)
                VALUES (:cj_id)
                ON CONFLICT (custom_json_id) DO UPDATE SET custom_json_id = EXCLUDED.custom_json_id
                RETURNING id
            """,
            cj_id=cj_id,
        )

    def push(self) -> None:
        OperationBase.pos_in_block += 1

        OperationBase.operation_id = Db.instance().query_one(
            sql='SELECT operation_id FROM hafd.operation_id(:block_num, :pos_in_block);',
            block_num=self.block_number,
            pos_in_block=OperationBase.pos_in_block,
        )

        log.info(
            f'Attempting to push mocked {self.__class__.__name__} - type: {self.type} id: {OperationBase.operation_id}'
        )

        custom_json_type_id = self._resolve_custom_json_type_id()

        sql = """
INSERT INTO
    hafd.operations (id, trx_in_block, op_pos, op_type_id, body_binary, custom_json_type_id)
VALUES
    (:id, -2, -2, :op_type_id, :body :: jsonb :: hafd.operation, :cj_type_id);
"""
        Db.instance().query(
            sql=sql,
            id=OperationBase.operation_id,
            op_type_id=self.type.value,
            body=json.dumps(self.body),
            cj_type_id=custom_json_type_id,
        )

        # account ops
        account_name = None
        if self.type == OperationType.POW:
            account_name = self.body['value']['worker_account']
        elif self.type == OperationType.POW_2:
            account_name = self.body['value']['work']['value']['input']['worker_account']
        elif self.type == OperationType.ACCOUNT_CREATE:
            account_name = self.body['value']['new_account_name']
        elif self.type == OperationType.ACCOUNT_CREATE_WITH_DELEGATION:
            account_name = self.body['value']['new_account_name']
        elif self.type == OperationType.CREATE_CLAIMED_ACCOUNT:
            account_name = self.body['value']['new_account_name']

        if account_name:
            log.info(f'Account create operation with account name: {account_name}')
            AccountMock(block_number=self.block_number, name=account_name).push()

        log.info(f'{self.__class__.__name__} pushed successfully!')


class VirtualOperationMock(OperationBase):
    def __init__(self, block_number: int, body: dict):
        super().__init__(block_number=block_number, body=body)
        self._type = VirtualOperationType.from_name(operation_name=body['type'])

    @property
    def type(self) -> Optional[VirtualOperationType]:
        return self._type


class OperationMock(OperationBase):
    def __init__(self, block_number: int, body: dict):
        super().__init__(block_number=block_number, body=body)
        self._type = OperationType.from_name(operation_name=body['type'])

    @property
    def type(self) -> Optional[OperationType]:
        return self._type


class TransactionMock:
    def __init__(self, block_number: int, body: dict):
        self._block_number = block_number
        self._body = body

    @property
    def block_number(self) -> int:
        return self._block_number

    @property
    def ref_block_num(self) -> int:
        return self._body['ref_block_num']

    @property
    def ref_block_prefix(self) -> int:
        return self._body['ref_block_prefix']

    @property
    def expiration(self) -> str:
        return self._body['expiration']

    @property
    def hash(self) -> str:
        to_hash = f'{self._block_number}{json.dumps(self._body)}'.encode()
        sha1 = hashlib.sha1(to_hash)
        return sha1.hexdigest()

    def get_next_operation(self) -> Iterator[OperationMock]:
        for operation_raw in self._body['operations']:
            operation = OperationMock(self._block_number, body=operation_raw)
            if not operation.type:
                continue
            yield operation

    def push(self) -> None:
        sql = """
INSERT INTO
    hafd.transactions (block_num, trx_in_block, trx_hash, ref_block_num, ref_block_prefix, expiration, signature)
VALUES
    (:block_num, -2, :trx_hash, :ref_block_num, :ref_block_prefix, :expiration, NULL);
"""

        log.info(f'Attempting to push mocked TRANSACTION with hash: {self.hash}')

        Db.instance().query(
            sql=sql,
            block_num=self.block_number,
            trx_hash=self.hash,
            ref_block_num=self.ref_block_num,
            ref_block_prefix=self.ref_block_prefix,
            expiration=self.expiration,
        )

        log.info('TRANSACTION pushed successfully!')


class BlockMock:
    def __init__(self, block_number: int, block_data: dict, virtual_ops: Optional[dict] = None):
        self._block_number = block_number
        self._blocks_data = block_data
        self._virtual_ops = virtual_ops if virtual_ops is not None else {}

    @property
    def block_number(self) -> int:
        return self._block_number

    def get_next_virtual_operation(self) -> Iterator[VirtualOperationMock]:
        for virtual_operation_raw in self._virtual_ops:
            vop_mock = VirtualOperationMock(block_number=self.block_number, body=virtual_operation_raw)
            if not vop_mock.type:
                continue
            yield vop_mock

    def get_next_transaction(self) -> Iterator[TransactionMock]:
        for transaction_body in self._blocks_data['transactions']:
            yield TransactionMock(block_number=self._block_number, body=transaction_body)


class BlockMockAfterDb:
    def __init__(self, block_number: int, hash: str, previous_hash: str, created_at: datetime.datetime):
        self._block_number = block_number
        self._hash = hash
        self._previous_hash = previous_hash
        self._created_at = created_at

    @property
    def block_number(self) -> int:
        return self._block_number

    @property
    def hash(self) -> str:
        return self._hash

    @property
    def previous_hash(self) -> str:
        return self._previous_hash

    @property
    def created_at(self) -> datetime.datetime:
        return self._created_at

    def push(self) -> None:
        initminer_account_id = 3

        sql = f"""
INSERT INTO hafd.blocks (num, hash, prev, created_at, producer_account_id, transaction_merkle_root, extensions,
                         witness_signature, signing_key, hbd_interest_rate, total_vesting_fund_hive, total_vesting_shares,
                         total_reward_fund_hive, virtual_supply, current_supply, current_hbd_supply, dhf_interval_ledger)
VALUES (:num, :hash, :prev, :created_at, {initminer_account_id}, 'mocked'::bytea, NULL, 'mocked'::bytea, 'mocked', 1000, 1000,
                         1000000, 1000, 1000, 1000, 2000, 2000);
"""

        log.info(f'Attempting to push mocked BLOCK with number: {self.block_number}')

        Db.instance().query(
            sql=sql,
            num=self.block_number,
            hash=self.hash,
            prev=self.previous_hash,
            created_at=self.created_at,
        )

        log.info('BLOCK pushed successfully!')

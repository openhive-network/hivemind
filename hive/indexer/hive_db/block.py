import logging

import ujson as json

from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType

log = logging.getLogger(__name__)


class VirtualOperationHiveDb(Operation):
    def __init__(self, operation_type, operation_body):
        self._operation_type = operation_type
        self._operation_body = operation_body

    def get_type(self):
        return self._operation_type

    def get_body(self):
        body = json.loads(str(self._operation_body))
        return body['value']


class OperationHiveDb(Operation):
    def __init__(self, operation_type, operation_body):
        self._operation_type = operation_type
        self._operation_body = operation_body

    def get_type(self):
        return self._operation_type

    def get_body(self):
        body = json.loads(self._operation_body)
        return body['value']


class TransactionHiveDb(Transaction):
    def __init__(self, block_num, operations, operation_id_to_enum):
        self._block_num = block_num
        self._operations = operations
        self._operation_id_to_enum = operation_id_to_enum

    def get_id(self):
        return 0  # it is a fake transactions which returns all operations

    def get_next_operation(self):
        if not self._operations:
            return None

        for operation in self._operations:
            operation_type = self._operation_id_to_enum(operation['operation_type_id'])
            if type(operation_type) != OperationType:
                continue

            ret_operation = OperationHiveDb(operation_type, operation['body'])
            yield ret_operation


class BlockHiveDb(Block):
    def __init__(
        self,
        num,
        date,
        hash,
        previous_block_hash,
        operations,
        opertion_id_to_enum,
    ):

        self._num = num
        self._date = date
        self._hash = hash.hex()
        self._prev_hash = previous_block_hash.hex()
        self._operations = operations
        self._operation_id_to_enum = opertion_id_to_enum

    def get_num(self):
        return self._num

    def get_next_vop(self):
        if not self._operations or self._operations is None:
            return None

        for virtual_operation in self._operations:
            operation_type = self._operation_id_to_enum(virtual_operation['operation_type_id'])
            if type(operation_type) != VirtualOperationType:
                continue

            virtual_op = VirtualOperationHiveDb(operation_type, virtual_operation['body'])
            yield virtual_op

    def get_date(self):
        return self._date

    def get_hash(self):
        return self._hash

    def get_previous_block_hash(self):
        return self._prev_hash

    def get_next_transaction(self):
        if not self._operations:
            return None
        trans = TransactionHiveDb(
            self.get_num(), self._operations, self._operation_id_to_enum
        )
        yield trans

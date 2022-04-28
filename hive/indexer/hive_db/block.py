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
    def __init__(self, block_num, operations, firts_operation_idx, operation_id_to_enum):
        self._block_num = block_num
        self._operations = operations
        self._first_operation_idx = firts_operation_idx
        self._operation_id_to_enum = operation_id_to_enum

    def get_id(self):
        return 0  # it is a fake transactions which returns all operations

    def get_next_operation(self):
        if self._first_operation_idx is None:
            return None

        for op_idx in range(self._first_operation_idx, len(self._operations)):
            assert self._operations[op_idx]['block_num'] >= self._block_num

            if self._operations[op_idx]['block_num'] > self._block_num:
                break

            operation_type = self._operation_id_to_enum(self._operations[op_idx]['operation_type_id'])
            if type(operation_type) != OperationType:
                continue

            operation = OperationHiveDb(operation_type, self._operations[op_idx]['body'])
            yield operation


class BlockHiveDb(Block):
    def __init__(
        self,
        num,
        date,
        hash,
        previous_block_hash,
        number_of_transactions,
        number_of_operations,
        operations,
        first_operation_idx,
        opertion_id_to_enum,
    ):

        self._num = num
        self._date = date
        self._hash = hash.hex()
        self._prev_hash = previous_block_hash.hex()
        self._number_of_transactions = number_of_transactions
        self._number_of_operations = number_of_operations
        self._operations = operations
        self._first_operation_idx = first_operation_idx
        self._operation_id_to_enum = opertion_id_to_enum

    def get_num(self):
        return self._num

    def get_next_vop(self):
        if self._first_operation_idx is None:
            return None

        for virtual_op_idx in range(self._first_operation_idx, len(self._operations)):
            if self._operations[virtual_op_idx]['block_num'] > self.get_num():
                break

            operation_type = self._operation_id_to_enum(self._operations[virtual_op_idx]['operation_type_id'])
            if type(operation_type) != VirtualOperationType:
                continue

            virtual_op = VirtualOperationHiveDb(operation_type, self._operations[virtual_op_idx]['body'])
            yield virtual_op

    def get_date(self):
        return self._date

    def get_hash(self):
        return self._hash

    def get_previous_block_hash(self):
        return self._prev_hash

    def get_number_of_transactions(self):
        return self._number_of_transactions

    def get_number_of_operations(self):
        return self._number_of_operations

    def get_next_transaction(self):
        if self._first_operation_idx is None:
            return None
        trans = TransactionHiveDb(
            self.get_num(), self._operations, self._first_operation_idx, self._operation_id_to_enum
        )
        yield trans

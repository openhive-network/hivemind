import logging

from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType

log = logging.getLogger(__name__)


class VirtualOperationMock(Operation):
    def __init__(self, operation_name, operation_body):
        self._operation_type = VirtualOperationType.from_name(operation_name)
        self._operation_body = operation_body

    def get_type(self):
        return self._operation_type

    def get_body(self):
        return self._operation_body


class OperationMock(Operation):
    def __init__(self, operation_name, operation_body):
        self._operation_type = OperationType.from_name(operation_name)
        self._operation_body = operation_body

    def get_type(self):
        return self._operation_type

    def get_body(self):
        return self._operation_body


class TransactionMock(Transaction):
    def __init__(self, id, transaction):
        self._id = id
        self._transaction = transaction

    def get_id(self):
        return self._id

    def get_next_operation(self):
        for raw_operation in self._transaction['operations']:
            operation = OperationMock(raw_operation['type'], raw_operation['value'])
            if not operation.get_type():
                continue
            yield operation


class BlockMock(Block):
    def __init__(self, block_data, virtual_ops):
        """
        block_data - raw format of the blocks
        virtual_ops - list of virtual ops in the blocks
        previous_block_hash - hash of the previous block
        """
        self._blocks_data = block_data
        self._virtual_ops = virtual_ops

    def get_num(self):
        return int(self._blocks_data['block_id'][:8], base=16)

    def get_date(self):
        return self._blocks_data['timestamp']

    def get_hash(self):
        return self._blocks_data['block_id']

    def get_previous_block_hash(self):
        return self._blocks_data['previous']

    def get_next_vop(self):
        for vop in self._virtual_ops:
            vop_object = VirtualOperationMock(vop['type'], vop['value'])
            if not vop_object.get_type():
                continue
            yield vop_object

    def get_next_transaction(self):
        for tx_idx, tx in enumerate(self._blocks_data['transactions']):
            yield TransactionMock(tx_idx, tx)


class ExtendedByMockBlockAdapter(Block):
    def __init__(self, block, extended_block):
        assert issubclass(type(block), Block)
        assert issubclass(type(extended_block), Block)

        self._wrapped_block = block
        self._extended_block = extended_block

    def get_num(self):
        return self._wrapped_block.get_num()

    def get_next_vop(self):
        for vop in self._wrapped_block.get_next_vop():
            yield vop
        for vop in self._extended_block.get_next_vop():
            yield vop

    def get_date(self):
        return self._wrapped_block.get_date()

    def get_hash(self):
        return self._wrapped_block.get_hash()

    def get_previous_block_hash(self):
        return self._wrapped_block.get_previous_block_hash()

    def get_next_transaction(self):
        for transaction in self._wrapped_block.get_next_transaction():
            yield transaction
        for transaction in self._extended_block.get_next_transaction():
            yield transaction

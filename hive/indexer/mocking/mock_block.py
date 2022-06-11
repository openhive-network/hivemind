from hive.indexer.block import Block


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

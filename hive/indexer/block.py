import logging
import queue
from abc import ABC, abstractmethod
from enum import Enum

from hive.steem.signal import can_continue_thread

log = logging.getLogger(__name__)


class VirtualOperationType(Enum):
    AUTHOR_REWARD = 1
    COMMENT_REWARD = 2
    EFFECTIVE_COMMENT_VOTE = 3
    COMMENT_PAYOUT_UPDATE = 4
    INEFFECTIVE_DELETE_COMMENT = 5

    def from_name(operation_name):
        if operation_name == 'author_reward_operation':
            return VirtualOperationType.AUTHOR_REWARD
        if operation_name == 'comment_reward_operation':
            return VirtualOperationType.COMMENT_REWARD
        if operation_name == 'effective_comment_vote_operation':
            return VirtualOperationType.EFFECTIVE_COMMENT_VOTE
        if operation_name == 'ineffective_delete_comment_operation':
            return VirtualOperationType.INEFFECTIVE_DELETE_COMMENT
        if operation_name == 'comment_payout_update_operation':
            return VirtualOperationType.COMMENT_PAYOUT_UPDATE

        return None


class OperationType(Enum):
    POW = 1
    POW_2 = 2
    ACCOUNT_CREATE = 3
    ACCOUNT_CREATE_WITH_DELEGATION = 4
    CREATE_CLAIMED_ACCOUNT = 5
    ACCOUNT_UPDATE = 6
    ACCOUNT_UPDATE_2 = 7
    COMMENT = 8
    DELETE_COMMENT = 9
    COMMENT_OPTION = 10
    VOTE = 11
    TRANSFER = 12
    CUSTOM_JSON = 13

    def from_name(operation_name):
        if operation_name == 'pow_operation':
            return OperationType.POW
        if operation_name == 'pow2_operation':
            return OperationType.POW_2
        if operation_name == 'account_create_operation':
            return OperationType.ACCOUNT_CREATE
        if operation_name == 'account_create_with_delegation_operation':
            return OperationType.ACCOUNT_CREATE_WITH_DELEGATION
        if operation_name == 'create_claimed_account_operation':
            return OperationType.CREATE_CLAIMED_ACCOUNT
        if operation_name == 'account_update_operation':
            return OperationType.ACCOUNT_UPDATE
        if operation_name == 'account_update2_operation':
            return OperationType.ACCOUNT_UPDATE_2
        if operation_name == 'comment_operation':
            return OperationType.COMMENT
        if operation_name == 'delete_comment_operation':
            return OperationType.DELETE_COMMENT
        if operation_name == 'comment_options_operation':
            return OperationType.COMMENT_OPTION
        if operation_name == 'vote_operation':
            return OperationType.VOTE
        if operation_name == 'transfer_operation':
            return OperationType.TRANSFER
        if operation_name == 'custom_json_operation':
            return OperationType.CUSTOM_JSON
        # for operations not supported by hivemind
        return None


class Block(ABC):
    """Represents one block of the chain"""

    @abstractmethod
    def get_num(self):
        pass

    @abstractmethod
    def get_next_vop(self):
        pass

    @abstractmethod
    def get_date(self):
        pass

    @abstractmethod
    def get_hash(self):
        pass

    @abstractmethod
    def get_previous_block_hash(self):
        pass

    @abstractmethod
    def get_number_of_transactions(self):
        pass

    @abstractmethod
    def get_number_of_operations(self):
        pass

    @abstractmethod
    def get_next_transaction(self):
        pass


class Operation(ABC):
    @abstractmethod
    def get_type(self):
        pass

    @abstractmethod
    def get_body(self):
        pass


class Transaction(ABC):
    @abstractmethod
    def get_id(self):
        pass

    @abstractmethod
    def get_next_operation(self):
        pass


class BlockWrapper(Block):
    def __init__(self, wrapped_block):
        """
        wrapped_block - block which is wrapped
        """
        assert wrapped_block
        self.wrapped_block = wrapped_block

    def get_num(self):
        return self.wrapped_block.get_num()

    def get_next_vop(self):
        return self.wrapped_block.get_next_vop()

    def get_date(self):
        return self.wrapped_block.get_date()

    def get_hash(self):
        return self.wrapped_block.get_hash()

    def get_previous_block_hash(self):
        return self.wrapped_block.get_previous_block_hash()

    def get_number_of_transactions(self):
        return self.wrapped_block.get_number_of_transactions()

    def get_number_of_operations(self):
        return self.wrapped_block.get_number_of_operations()

    def get_next_transaction(self):
        return self.wrapped_block.get_next_transaction()


class BlocksProviderBase(ABC):
    def __init__(self):
        self._blocks_queue_size = 1500
        self._blocks_data_queue_size = 1500
        self._operations_queue_size = 1500

    @abstractmethod
    def start(self):
        """Shall start threads and returns lists of futures"""
        pass

    @abstractmethod
    def get(self, number_of_blocks):
        """Returns lists of blocks"""
        pass

    @staticmethod
    def _get_from_queue(data_queue, number_of_elements):
        """Tool function to get elements from queue"""
        ret = []
        for element in range(number_of_elements):
            while can_continue_thread():
                try:
                    ret.append(data_queue.get(True, 1))
                    data_queue.task_done()
                except queue.Empty:
                    continue
                break
        return ret

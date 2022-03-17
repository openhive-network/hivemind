from abc import ABC, abstractmethod
from enum import Enum

import logging
import queue

log = logging.getLogger(__name__)


class VirtualOperationType(Enum):
    AuthorReward = 1
    CommentReward = 2
    EffectiveCommentVote = 3
    CommentPayoutUpdate = 4
    IneffectiveDeleteComment = 5

    def from_name(operation_name):
        if operation_name == 'author_reward_operation':
            return VirtualOperationType.AuthorReward
        if operation_name == 'comment_reward_operation':
            return VirtualOperationType.CommentReward
        if operation_name == 'effective_comment_vote_operation':
            return VirtualOperationType.EffectiveCommentVote
        if operation_name == 'ineffective_delete_comment_operation':
            return VirtualOperationType.IneffectiveDeleteComment
        if operation_name == 'comment_payout_update_operation':
            return VirtualOperationType.CommentPayoutUpdate

        return None


class OperationType(Enum):
    Pow = 1
    Pow2 = 2
    AccountCreate = 3
    AccountCreateWithDelegation = 4
    CreateClaimedAccount = 5
    AccountUpdate = 6
    AccountUpdate2 = 7
    Comment = 8
    DeleteComment = 9
    CommentOption = 10
    Vote = 11
    Transfer = 12
    CustomJson = 13

    def from_name(operation_name):
        if operation_name == 'pow_operation':
            return OperationType.Pow
        if operation_name == 'pow2_operation':
            return OperationType.Pow2
        if operation_name == 'account_create_operation':
            return OperationType.AccountCreate
        if operation_name == 'account_create_with_delegation_operation':
            return OperationType.AccountCreateWithDelegation
        if operation_name == 'create_claimed_account_operation':
            return OperationType.CreateClaimedAccount
        if operation_name == 'account_update_operation':
            return OperationType.AccountUpdate
        if operation_name == 'account_update2_operation':
            return OperationType.AccountUpdate2
        if operation_name == 'comment_operation':
            return OperationType.Comment
        if operation_name == 'delete_comment_operation':
            return OperationType.DeleteComment
        if operation_name == 'comment_options_operation':
            return OperationType.CommentOption
        if operation_name == 'vote_operation':
            return OperationType.Vote
        if operation_name == 'transfer_operation':
            return OperationType.Transfer
        if operation_name == 'custom_json_operation':
            return OperationType.CustomJson
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
    def __init__(self, breaker, exception_reporter):
        """
        breaker - callable, returns true when sync can continue, false when break was requested
        exception_reporter - callable, use to inform about undesire exception in a synchronizaton thread
        """
        assert breaker
        assert exception_reporter

        self._breaker = breaker
        self._exception_reporter = exception_reporter

        self._blocks_queue_size = 1500
        self._blocks_data_queue_size = 1500

        self._operations_queue_size = 1500

    def report_exception():
        self._exception_reporter()

    @abstractmethod
    def start(self):
        """Shall start threads and returns lists of futures"""
        pass

    @abstractmethod
    def get(self, number_of_blocks):
        """Returns lists of blocks"""
        pass

    def _get_from_queue(self, data_queue, number_of_elements):
        """Tool function to get elements from queue"""
        ret = []
        for element in range(number_of_elements):
            if not self._breaker():
                break
            while self._breaker():
                try:
                    ret.append(data_queue.get(True, 1))
                    data_queue.task_done()
                except queue.Empty:
                    continue
                break
        return ret

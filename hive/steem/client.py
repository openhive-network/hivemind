"""Tight and reliable steem API client for hive indexer."""
import logging

from time import perf_counter as perf
from decimal import Decimal

from hive.utils.stats import Stats
from hive.utils.normalize import parse_amount, steem_amount, vests_amount
from hive.steem.http_client import HttpClient
from hive.steem.block.stream import BlockStream

logger = logging.getLogger(__name__)

class SteemClient:
    """Handles upstream calls to jussi/steemd, with batching and retrying."""
    # dangerous default value of url but it should be fine since we are not writting to it
    def __init__(self, url={"default" : 'https://api.hive.blog'}, max_batch=50, max_workers=1):
        assert url, 'steem-API endpoints undefined'
        assert "default" in url, "Url should have default endpoint defined"
        assert max_batch > 0 and max_batch <= 5000
        assert max_workers > 0 and max_workers <= 64

        self._max_batch = max_batch
        self._max_workers = max_workers
        self._client = dict()
        for endpoint, endpoint_url in url.items():
            logger.info("Endpoint %s will be routed to node %s" % (endpoint, endpoint_url))
            self._client[endpoint] = HttpClient(nodes=[endpoint_url])

    def get_accounts(self, acc):
        accounts = [v for v in acc if v != '']
        """Fetch multiple accounts by name."""
        assert accounts, "no accounts passed to get_accounts"
        assert len(accounts) <= 1000, "max 1000 accounts"
        ret = self.__exec('get_accounts', [accounts])
        assert len(accounts) == len(ret), ("requested %d accounts got %d"
                                           % (len(accounts), len(ret)))
        return ret

    def get_all_account_names(self):
        """Fetch all account names."""
        ret = []
        names = self.__exec('lookup_accounts', ['', 1000])
        while names:
            ret.extend(names)
            names = self.__exec('lookup_accounts', [names[-1], 1000])[1:]
        return ret

    def get_content_batch(self, tuples):
        """Fetch multiple comment objects."""
        raise NotImplementedError("get_content is not implemented in hived")

    def get_block(self, num, strict=True):
        """Fetches a single block.

        If the result does not contain a `block` key, it's assumed
        this block does not yet exist and None is returned.
        """
        result = self.__exec('get_block', {'block_num': num})
        if 'block' in result:
            return result['block']
        elif strict:
            raise Exception('block %d not available' % num)
        else:
            return None

    def stream_blocks(self, start_from, trail_blocks=0, max_gap=100):
        """Stream blocks. Returns a generator."""
        return BlockStream.stream(self, start_from, trail_blocks, max_gap)

    def _gdgp(self):
        ret = self.__exec('get_dynamic_global_properties')
        assert 'time' in ret, "gdgp invalid resp: %s" % ret
        return ret

    def head_time(self):
        """Get timestamp of head block"""
        return self._gdgp()['time']

    def head_block(self):
        """Get head block number"""
        return self._gdgp()['head_block_number']

    def last_irreversible(self):
        """Get last irreversible block"""
        return self._gdgp()['last_irreversible_block_num']

    def gdgp_extended(self):
        """Get dynamic global props without the cruft plus useful bits."""
        dgpo = self._gdgp()

        # remove unused/deprecated keys
        unused = ['total_pow', 'num_pow_witnesses', 'confidential_supply',
                  'confidential_sbd_supply', 'total_reward_fund_steem',
                  'total_reward_shares2']
        for key in unused:
            if key in dgpo:
                del dgpo[key]

        return {
            'dgpo': dgpo,
            'usd_per_steem': self._get_feed_price(),
            'sbd_per_steem': self._get_steem_price(),
            'steem_per_mvest': SteemClient._get_steem_per_mvest(dgpo)}

    @staticmethod
    def _get_steem_per_mvest(dgpo):
        steem = steem_amount(dgpo['total_vesting_fund_hive'])
        mvests = vests_amount(dgpo['total_vesting_shares']) / Decimal(1e6)
        return "%.6f" % (steem / mvests)

    def _get_feed_price(self):
        # TODO: add latest feed price: get_feed_history.price_history[0]
        feed = self.__exec('get_feed_history')['current_median_history']
        units = dict([parse_amount(feed[k])[::-1] for k in ['base', 'quote']])
        if 'TBD' in units and 'TESTS' in units:
            price = units['TBD'] / units['TESTS']
        else:
            price = units['HBD'] / units['HIVE']
        return "%.6f" % price

    def _get_steem_price(self):
        orders = self.__exec('get_order_book', [1])
        if orders['asks'] and orders['bids']:
            ask = Decimal(orders['asks'][0]['real_price'])
            bid = Decimal(orders['bids'][0]['real_price'])
            price = (ask + bid) / 2
            return "%.6f" % price
        return "0"

    def get_blocks_range(self, lbound, ubound):
        """Retrieves blocks in the range of [lbound, ubound)."""
        block_nums = range(lbound, ubound)
        blocks = {}

        batch_params = [{'block_num': i} for i in block_nums]
        for result in self.__exec_batch('get_block', batch_params):
            assert 'block' in result, "result w/o block key: %s" % result
            block = result['block']
            num = int(block['block_id'][:8], base=16)
            blocks[num] = block

        return [blocks[x] for x in block_nums]

    def get_virtual_operations(self, block):
        """ Get virtual ops from block """
        result = self.__exec('get_ops_in_block', {"block_num":block, "only_virtual":True})
        tracked_ops = ['author_reward_operation', 'comment_reward_operation', 'effective_comment_vote_operation', 'comment_payout_update_operation', 'ineffective_delete_comment_operation']
        ret = []
        result = result['ops'] if 'ops' in result else []
        for vop in result:
            if vop['op']['type'] in tracked_ops:
                ret.append(vop['op'])
        return ret

    def enum_virtual_ops(self, begin_block, end_block):
        """ Get virtual ops for range of blocks """
        ret = {}

        from_block = begin_block

        #According to definition of hive::plugins::acount_history::enum_vops_filter:

        author_reward_operation                 = 0x000002
        comment_reward_operation                = 0x000008
        effective_comment_vote_operation        = 0x400000
        comment_payout_update_operation         = 0x000800
        ineffective_delete_comment_operation    = 0x800000

        tracked_ops_filter = author_reward_operation | comment_reward_operation | effective_comment_vote_operation | comment_payout_update_operation | ineffective_delete_comment_operation
        tracked_ops = ['author_reward_operation', 'comment_reward_operation', 'effective_comment_vote_operation', 'comment_payout_update_operation', 'ineffective_delete_comment_operation']

        resume_on_operation = 0

        while from_block < end_block:
            call_result = self.__exec('enum_virtual_ops', {"block_range_begin":from_block, "block_range_end":end_block
                , "group_by_block": True, "operation_begin": resume_on_operation, "limit": 1000, "filter": tracked_ops_filter
            })

            one_block_ops = {opb["block"] : {"timestamp":opb["timestamp"], "ops":[op["op"] for op in opb["ops"]]} for opb in call_result["ops_by_block"]}

            if one_block_ops:
                first_block = list(one_block_ops.keys())[0];
                # if we continue collecting ops from previous iteration
                if first_block in ret:
                    ret.update( { first_block : { "timestamp":ret[ first_block ]["timestamp"], "ops":ret[ first_block ]["ops"] + one_block_ops[ first_block ]["ops"]} } )
                    one_block_ops.pop( first_block, None )
            ret.update( one_block_ops )

            resume_on_operation = call_result['next_operation_begin'] if 'next_operation_begin' in call_result else 0


            next_block = call_result['next_block_range_begin']

            # Move to next block only if operations from current one have been processed completely.
            from_block = next_block

        return ret

    def get_comment_pending_payouts(self, comments):
        """ Get comment pending payout data """
        ret = self.__exec('get_comment_pending_payouts', {'comments':comments})
        return ret['cashout_infos']

    def __exec(self, method, params=None):
        """Perform a single steemd call."""
        start = perf()
        result = None
        if method in self._client:
            result = self._client[method].exec(method, params)
        else:
            result = self._client["default"].exec(method, params)
        items = len(params[0]) if method == 'get_accounts' else 1
        Stats.log_steem(method, perf() - start, items)
        return result

    def __exec_batch(self, method, params):
        """Perform batch call. Based on config uses either batch or futures."""
        start = perf()

        result = []
        if method in self._client:
            for part in self._client[method].exec_multi(
                    method,
                    params,
                    max_workers=self._max_workers,
                    batch_size=self._max_batch):
                result.extend(part)
        else:
            for part in self._client["default"].exec_multi(
                    method,
                    params,
                    max_workers=self._max_workers,
                    batch_size=self._max_batch):
                result.extend(part)

        Stats.log_steem(method, perf() - start, len(params))
        return result

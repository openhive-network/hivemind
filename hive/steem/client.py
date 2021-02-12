"""Tight and reliable steem API client for hive indexer."""

from hive.indexer.mock_data_provider import MockDataProviderException
import logging

from time import perf_counter as perf
from decimal import Decimal

from hive.utils.stats import Stats
from hive.utils.normalize import parse_amount, steem_amount, vests_amount
from hive.steem.http_client import HttpClient, BreakHttpRequestOnDemandException
from hive.indexer.mock_block_provider import MockBlockProvider
from hive.indexer.mock_vops_provider import MockVopsProvider

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

    def stream_blocks(self, conf, start_from, breaker, exception_reporter, trail_blocks=0, max_gap=100, do_stale_block_check=True):
        """Stream blocks. Returns a generator."""
        return BlockStream.stream(conself, start_from, breaker, exception_reporter, trail_blocks, max_gap, do_stale_block_check)

    def _gdgp(self, breaker = None):
        ret = self.__exec('get_dynamic_global_properties', breaker=breaker)
        assert 'time' in ret, "gdgp invalid resp: %s" % ret
        mock_max_block_number = MockBlockProvider.get_max_block_number()
        if mock_max_block_number > ret['head_block_number']:
            ret['time'] = MockBlockProvider.get_block_data(mock_max_block_number)['timestamp']
        ret['head_block_number'] = max([int(ret['head_block_number']), mock_max_block_number])
        #ret['last_irreversible_block_num'] = max([int(ret['last_irreversible_block_num']), mock_max_block_number])
        return ret

    def head_block(self, breaker = None):
        """Get head block number"""
        return self._gdgp(breaker)['head_block_number']

    def last_irreversible(self, breaker):
        """Get last irreversible block"""
        return self._gdgp(breaker)['last_irreversible_block_num']

    def gdgp_extended(self, breaker = None):
        """Get dynamic global props without the cruft plus useful bits."""
        dgpo = self._gdgp(breaker)

        # remove unused/deprecated keys
        unused = ['total_pow', 'num_pow_witnesses', 'confidential_supply',
                  'confidential_sbd_supply', 'total_reward_fund_steem',
                  'total_reward_shares2']
        for key in unused:
            if key in dgpo:
                del dgpo[key]

        return {
            'dgpo': dgpo,
            'usd_per_steem': self._get_feed_price(breaker = breaker),
            'sbd_per_steem': self._get_steem_price(breaker = breaker),
            'steem_per_mvest': SteemClient._get_steem_per_mvest(dgpo)}

    @staticmethod
    def _get_steem_per_mvest(dgpo):
        steem = steem_amount(dgpo['total_vesting_fund_hive'])
        mvests = vests_amount(dgpo['total_vesting_shares']) / Decimal(1e6)
        return "%.6f" % (steem / mvests)

    def _get_feed_price(self, breaker = None):
        # TODO: add latest feed price: get_feed_history.price_history[0]
        feed = self.__exec('get_feed_history', breaker = breaker)['current_median_history']
        units = dict([parse_amount(feed[k])[::-1] for k in ['base', 'quote']])
        if 'TBD' in units and 'TESTS' in units:
            price = units['TBD'] / units['TESTS']
        else:
            price = units['HBD'] / units['HIVE']
        return "%.6f" % price

    def _get_steem_price(self, breaker = None):
        orders = self.__exec('get_order_book', [1], breaker =  breaker )
        if orders['asks'] and orders['bids']:
            ask = Decimal(orders['asks'][0]['real_price'])
            bid = Decimal(orders['bids'][0]['real_price'])
            price = (ask + bid) / 2
            return "%.6f" % price
        return "0"

    def get_blocks_range(self, lbound, ubound, breaker=None):
        """Retrieves blocks in the range of [lbound, ubound)."""
        block_nums = range(lbound, ubound)
        blocks = {}

        batch_params = [{'block_num': i} for i in block_nums]
        idx = 0
        for result in self.__exec_batch('get_block', batch_params, breaker):
            if not breaker():
                return []
            block_num = batch_params[idx]['block_num']
            if 'block' in result:
                block = result['block']
                num = int(block['block_id'][:8], base=16)
                assert block_num == num, "Reference block number and block number from result does not match"
                blocks[num] = block
                MockBlockProvider.set_last_real_block_num_date(num, block['timestamp'])
                data = MockBlockProvider.get_block_data(num)
                if data is not None:
                    blocks[num]["transactions"].extend(data["transactions"])
                    blocks[num]["transaction_ids"].extend(data["transaction_ids"])
            else:
                blocks[block_num] = MockBlockProvider.get_block_data(block_num, True)
            idx += 1

        return [blocks[x] for x in block_nums]

    def enum_virtual_ops(self, conf, begin_block, end_block, breaker = None):
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

        resume_on_operation = 0

        while from_block < end_block:
            if breaker is not None and not breaker():
                return {}
            try:
                call_result = self.__exec('enum_virtual_ops', {"block_range_begin":from_block, "block_range_end":end_block
                , "group_by_block": True, "include_reversible": True, "operation_begin": resume_on_operation, "limit": 1000, "filter": tracked_ops_filter
                }, breaker = breaker)
            except BreakHttpRequestOnDemandException:
                return {}

            if conf.get('log_virtual_op_calls'):
                call = """
                Call enum_virtual_ops:
                Query: {{"block_range_begin":{}, "block_range_end":{}, "group_by_block": True, "operation_begin": {}, "limit": 1000, "filter": {} }}
                Response: {}""".format ( from_block, end_block, resume_on_operation, tracked_ops_filter, call_result )
                logger.info( call )


            one_block_ops = {opb["block"] : {"timestamp":opb["timestamp"], "ops":[op["op"] for op in opb["ops"]]} for opb in call_result["ops_by_block"]}

            if one_block_ops:
                first_block = list(one_block_ops.keys())[0]
                # if we continue collecting ops from previous iteration
                if first_block in ret:
                    ret.update( { first_block : { "timestamp":ret[ first_block ]["timestamp"], "ops":ret[ first_block ]["ops"] + one_block_ops[ first_block ]["ops"]} } )
                    one_block_ops.pop( first_block, None )
            ret.update( one_block_ops )

            resume_on_operation = call_result['next_operation_begin'] if 'next_operation_begin' in call_result else 0

            next_block = call_result['next_block_range_begin']

            if next_block == 0:
                break

            if next_block < begin_block:
                logger.error( "Next next block nr {} returned by enum_virtual_ops is smaller than begin block {}.".format( next_block, begin_block ) )
                break

            # Move to next block only if operations from current one have been processed completely.
            from_block = next_block

        MockVopsProvider.add_mock_vops(ret, begin_block, end_block)

        return ret

    def __exec(self, method, params=None, breaker = None):
        """Perform a single steemd call."""
        start = perf()
        result = None
        if method in self._client:
            result = self._client[method].exec(method, params, breaker=breaker)
        else:
            result = self._client["default"].exec(method, params, breaker=breaker)
        items = len(params[0]) if method == 'get_accounts' else 1
        Stats.log_steem(method, perf() - start, items)
        return result

    def __exec_batch(self, method, params, breaker = None):
        """Perform batch call. Based on config uses either batch or futures."""
        start = perf()

        result = []
        if method in self._client:
            for part in self._client[method].exec_multi(
                    method,
                    params,
                    max_workers=self._max_workers,
                    batch_size=self._max_batch,
                    breaker = breaker):
                result.extend(part)
        else:
            for part in self._client["default"].exec_multi(
                    method,
                    params,
                    max_workers=self._max_workers,
                    batch_size=self._max_batch,
                    breaker = breaker):
                result.extend(part)

        Stats.log_steem(method, perf() - start, len(params))
        return result

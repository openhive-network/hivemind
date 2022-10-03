from hive.server.common.helpers import return_error_info
from hive.server.condenser_api.methods import _get_account_reputations_impl


@return_error_info
async def get_account_reputations(context, account_lower_bound: str = '', limit: int = 1000):
    db = context['db']
    return await _get_account_reputations_impl(db, False, account_lower_bound, limit)

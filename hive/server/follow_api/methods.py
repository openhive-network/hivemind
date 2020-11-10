from hive.server.condenser_api.methods import _get_account_reputations_impl
from hive.server.common.helpers import return_error_info

@return_error_info
async def get_account_reputations(context, account_lower_bound: str = '', limit: int = 1000):
    db = context['db']
    return await _get_account_reputations_impl(db, False, account_lower_bound, limit)

@return_error_info
async def get_feed_entries(context, account: str, start_entry_id: int, limit: int):
    """ Returns a list of entries in an account’s feed. """
    raise NotImplementedError()

@return_error_info
async def get_feed(context, account: str, start_entry_id: int, limit: int):
    """ Returns a list of items in an account’s feed. """
    raise NotImplementedError()

@return_error_info
async def get_blog_authors(context, blog_account: str):
    """ Returns a list of authors that have had their content reblogged on a given blog account. """
    raise NotImplementedError()

from hive.server.common.helpers import return_error_info
from hive.server.condenser_api.methods import _get_content_impl, _get_content_replies_impl


@return_error_info
async def get_discussion(context, author: str, permlink: str, observer=None):
    db = context['db']
    return await _get_content_impl(db, False, author, permlink, observer)


@return_error_info
async def get_content_replies(context, author: str, permlink: str):
    db = context['db']
    return await _get_content_replies_impl(db, False, author, permlink)

from hive.server.common.helpers import (
    ApiError,
    return_error_info,
    valid_account,
    valid_permlink)

@return_error_info
async def get_active_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post. """
    valid_account(author)
    valid_permlink(permlink)
    # TODO: body
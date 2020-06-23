from hive.server.common.helpers import (
    return_error_info,
    valid_account,
    valid_permlink)

@return_error_info
async def get_active_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post. """
    valid_account(author)
    valid_permlink(permlink)
    # TODO: body
    raise NotImplementedError()

@return_error_info
async def get_tags_used_by_author(context, author: str):
    """ Returns a list of tags used by an author. """
    raise NotImplementedError()

@return_error_info
async def get_discussions_by_active(context, tag: str, limit: int, filter_tags: list,
                                    select_authors: list, select_tags: list, truncate_body: int):
    """ Returns a list of discussions based on active. """
    raise NotImplementedError()

@return_error_info
async def get_discussions_by_cashout(context, tag: str, limit: int, filter_tags: list,
                                     select_authors: list, select_tags: list, truncate_body: int):
    """ Returns a list of discussions by cashout. """
    raise NotImplementedError()

@return_error_info
async def get_discussions_by_votes(context, tag: str, limit: int, filter_tags: list,
                                   select_authors: list, select_tags: list, truncate_body: int):
    """ Returns a list of discussions by votes. """
    raise NotImplementedError()

@return_error_info
async def get_discussions_by_children(context, tag: str, limit: int, filter_tags: list,
                                      select_authors: list, select_tags: list, truncate_body: int):
    """ Returns a list of discussions by children. """
    raise NotImplementedError()

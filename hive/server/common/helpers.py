"""Helpers for server/API functions."""

import re
from functools import wraps
import traceback
import logging
import datetime
from dateutil.relativedelta import relativedelta
from psycopg2.errors import RaiseException
from jsonrpcserver.exceptions import ApiError as RPCApiError

log = logging.getLogger(__name__)

class ApiError(Exception):
    """API-specific errors: unimplemented/bad params. Pass back to client."""
    # pylint: disable=unnecessary-pass
    pass

# values -32768..-32000 are reserved
ACCESS_TO_DELETED_POST_ERROR_CODE = -31999

def return_error_info(function):
    """Async API method decorator which catches and formats exceptions."""
    @wraps(function)
    async def wrapper(*args, **kwargs):
        """Catch ApiError and AssertionError (always due to user error)."""
        try:
            return await function(*args, **kwargs)
        except (RaiseException) as e:
            msg = e.diag.message_primary
            if 'was deleted' in msg:
                raise RPCApiError('Invalid parameters', ACCESS_TO_DELETED_POST_ERROR_CODE, msg)
            else:
                raise AssertionError(msg)
        except (ApiError, AssertionError, TypeError, Exception) as e:
            if isinstance(e, KeyError):
                #TODO: KeyError overloaded for method not found. Any KeyErrors
                #      captured in this decorater are likely irrelevant to
                #      json_rpc_server. Verify. (e.g. `KeyError: 'flag_weight'`)
                log.error("ERR3: %s\n%s", repr(e), traceback.format_exc())
                raise ApiError('ErrKey: ' + str(e))
            if isinstance(e, ApiError) and 'get_account_votes' in str(e):
                raise e
            if isinstance(e, AssertionError) and 'account not found' in str(e):
                raise e
            if isinstance(e, AssertionError) and 'community not found' in str(e):
                raise e
            if isinstance(e, TypeError) and 'unexpected keyword' not in str(e):
                # one specific TypeError we want to silence; others need a trace
                log.error("ERR1: %s\n%s", repr(e), traceback.format_exc())
                raise e
            if isinstance(e, AssertionError):
                log.error("ERR2: %s\n%s", repr(e), traceback.format_exc())
                raise e
            log.error("ERR0: %s\n%s", repr(e), traceback.format_exc())
            raise e
            #return {
            #    "error": {
            #        "code": -32000,
            #        "message": repr(e) + " (hivemind-beta)",
            #        "trace": traceback.format_exc()}}
    return wrapper

def json_date(date=None):
    """Given a db datetime, return a steemd/json-friendly version."""
    if not date or date == datetime.datetime.max: return '1969-12-31T23:59:59'
    return 'T'.join(str(date).split(' '))

def get_hive_accounts_info_view_query_string(names, lite = False):
    values = []
    for name in names:
      values.append("('{}')".format( name ))
    values_str = ','.join(values)
    sql = """
              SELECT *
              FROM {} v
              JOIN
                (
                  VALUES {}
                )T( _name ) ON v.name = T._name
          """.format( ( 'hive_accounts_info_view_lite' if lite else 'hive_accounts_info_view' ), values_str )
    return sql
   
def last_month():
    """Get the date 1 month ago."""
    return datetime.datetime.now() + relativedelta(months=-1)

def valid_account(name, allow_empty=False):
    """Returns validated account name or throws Assert."""
    if not name:
        assert allow_empty, 'invalid account (not specified)'
        return ""
    assert isinstance(name, str), "invalid account name type"
    assert 3 <= len(name) <= 16, "invalid account name length: `%s`" % name
    assert name[0] != '@', "invalid account name char `@`"
    assert re.match(r'^[a-z0-9-\.]+$', name), 'invalid account char'
    return name

def valid_permlink(permlink, allow_empty=False):
    """Returns validated permlink or throws Assert."""
    if not permlink:
        assert allow_empty, 'permlink cannot be blank'
        return ""
    assert isinstance(permlink, str), 'permlink must be string'
    assert len(permlink) <= 256, "invalid permlink length"
    return permlink

def valid_sort(sort, allow_empty=False):
    """Returns validated sort name or throws Assert."""
    if not sort:
        assert allow_empty, 'sort must be specified'
        return ""
    assert isinstance(sort, str), 'sort must be a string'
    # TODO: differentiate valid sorts on comm vs tag
    valid_sorts = ['trending', 'promoted', 'hot', 'created',
                   'payout', 'payout_comments', 'muted']
    assert sort in valid_sorts, 'invalid sort `%s`' % sort
    return sort

def valid_tag(tag, allow_empty=False):
    """Returns validated tag or throws Assert."""
    if not tag:
        assert allow_empty, 'tag was blank'
        return ""
    assert isinstance(tag, str), 'tag must be a string'
    assert re.match('^[a-z0-9-_]+$', tag), 'invalid tag `%s`' % tag
    return tag

def valid_number(num, default=None, name='integer value', lbound=None, ubound=None):
    """Given a user-provided number, return a valid int, or raise."""
    if not num and num != 0:
      assert default is not None, "%s must be provided" % name
      num = default
    try:
      num = int(num)
    except (TypeError, ValueError) as e:
      raise AssertionError(str(e))
    if lbound is not None and ubound is not None:
      assert lbound <= num and num <= ubound, "%s = %d outside valid range [%d:%d]" % (name, num, lbound, ubound)
    return num

def valid_limit(limit, ubound, default):
    return valid_number(limit, default, "limit", 1, ubound)

def valid_score(score, ubound, default):
    return valid_number(score, default, "score", 0, ubound)

def valid_truncate(truncate_body):
    return valid_number(truncate_body, 0, "truncate_body")

def valid_offset(offset, ubound=None):
    """Given a user-provided offset, return a valid int, or raise."""
    offset = int(offset)
    assert offset >= -1, "offset cannot be negative"
    if ubound is not None:
        assert offset <= ubound, "offset too large"
    return offset

def valid_follow_type(follow_type: str):
    """Ensure follow type is valid steemd type."""
    # ABW: should be extended with blacklists etc. (and those should be implemented as next 'state' values)
    supported_follow_types = dict(blog=1, ignore=2)
    assert follow_type in supported_follow_types, "Unsupported follow type, valid types: {}".format(", ".join(supported_follow_types.keys()))
    return supported_follow_types[follow_type]

def valid_date(date, allow_empty=False):
    """ Ensure that date is in correct format """
    if not date:
        assert allow_empty, 'Date is blank'
    check_date = False
    # check format "%Y-%m-%d %H:%M:%S"
    try:
        check_date = (date == datetime.datetime.strptime(date, "%Y-%m-%d %H:%M:%S").strftime('%Y-%m-%d %H:%M:%S'))
    except ValueError:
        check_date = False
    # if check failed for format above try another format
    # check format "%Y-%m-%dT%H:%M:%S"
    if not check_date:
        try:
            check_date = (date == datetime.datetime.strptime(date, "%Y-%m-%dT%H:%M:%S").strftime('%Y-%m-%dT%H:%M:%S'))
        except ValueError:
            pass

    assert check_date, "Date should be in format Y-m-d H:M:S or Y-m-dTH:M:S"

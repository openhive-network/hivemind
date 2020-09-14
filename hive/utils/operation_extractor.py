#!/usr/bin/python3

import logging
log = logging.getLogger(__name__)

def __extract_one(val) -> list:
    if type(val) == type(str()):
        return [val]
    else:
        return []

def __extract_list(val) -> list:
    for v in val:
        if type(v) != type(str()):
            return []
    return val

def __extract_dict(val, based_on_dict) -> list:
    ret = []
    for k, v in val.items():
        if k in based_on_dict.keys():
            ret.extend(based_on_dict[k](v))
        elif type(v) == type(dict()):
            ret.extend(__extract_dict(v, based_on_dict))
    return ret

def extract(_from, _name_dict):
    return __extract_dict(_from ,_name_dict)

FIELDS_WITH_NAMES = {
    "worker_account":           __extract_one,
    "from":                     __extract_one,
    "from_account":             __extract_one,
    "to":                       __extract_one,
    "to_account":               __extract_one,
    "recovery_account":         __extract_one,
    "account_to_recover":       __extract_one,
    "new_recovery_account":     __extract_one,
    "account":                  __extract_one,
    "witness":                  __extract_one,
    "creator":                  __extract_one,
    "new_account_name":         __extract_one,
    "author":                   __extract_one,
    "voter":                    __extract_one,
    "publisher":                __extract_one,
    "owner":                    __extract_one,
    "required_auths":           __extract_list,
    "required_posting_auths":   __extract_list
}

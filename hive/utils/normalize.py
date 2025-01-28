"""Methods to parse steemd values and clean strings."""

from datetime import datetime
import decimal
import logging
import math

from pytz import utc
import ujson as json

NAI_MAP = {
    '@@000000013': 'HBD',
    '@@000000021': 'HIVE',
    '@@000000037': 'VESTS',
}

NAI_PRECISION = {
    '@@000000013': 3,
    '@@000000021': 3,
    '@@000000037': 6,
}

UNIT_NAI = {'HBD': '@@000000013', 'HIVE': '@@000000021', 'VESTS': '@@000000037'}

# convert special chars into their octal formats recognized by sql
SPECIAL_CHARS = {
    "\x00": " ",
    # nul char cannot be stored in string column (ABW: if we ever find the need to store nul chars we'll need bytea, not text)
    "\r": "\\015",
    "\n": "\\012",
    "\v": "\\013",
    "\f": "\\014",
    "\\": "\\134",
    "'": "\\047",
    "%": "\\045",
    "_": "\\137",
    ":": "\\072",
}


def to_nai(value):
    """Convert various amount notation to nai notation"""
    ret = None
    if isinstance(value, dict):
        assert 'amount' in value, "amount not found in dict"
        assert 'precision' in value, "precision not found in dict"
        assert 'nai' in value, "nai not found in dict"
        ret = value

    elif isinstance(value, str):
        raw_amount, unit = value.split(' ')
        assert unit in UNIT_NAI, f"Unknown unit {unit}"
        nai = UNIT_NAI[unit]
        precision = NAI_PRECISION[nai]
        satoshis = int(decimal.Decimal(raw_amount) * (10**precision))
        ret = {'amount': str(satoshis), 'nai': nai, 'precision': precision}

    elif isinstance(value, list):
        satoshis, precision, nai = value
        assert nai in NAI_MAP, f"Unknown NAI {nai}"

    else:
        raise Exception(f"Invalid input amount {repr(value)}")
    return ret


def escape_characters(text):
    """Escape special charactes"""
    assert isinstance(text, str), f"Expected string got: {type(text)}"
    if len(text.strip()) == 0:
        return "'" + text + "'"

    ret = "E'"

    for ch in text:
        if ch in SPECIAL_CHARS:
            dw = SPECIAL_CHARS[ch]
            ret = ret + dw
        else:
            ordinal = ord(ch)
            if ordinal <= 0x80 and ch.isprintable():
                ret = ret + ch
            else:
                hexstr = hex(ordinal)[2:]
                i = len(hexstr)
                max = 4
                escaped_value = '\\u'
                if i > max:
                    max = 8
                    escaped_value = '\\U'
                while i < max:
                    escaped_value += '0'
                    i += 1
                escaped_value += hexstr
                ret = ret + escaped_value

    ret = ret + "'"
    return ret


def vests_amount(value):
    """Returns a decimal amount, asserting units are VESTS"""
    return parse_amount(value, 'VESTS')


def steem_amount(value):
    """Returns a decimal amount, asserting units are HIVE"""
    return parse_amount(value, 'HIVE')


def sbd_amount(value):
    """Returns a decimal amount, asserting units are HBD"""
    return parse_amount(value, 'HBD')


def parse_amount(value, expected_unit=None):
    """Parse steemd-style amout/asset value, return (decimal, name)."""
    if isinstance(value, dict):
        value = [value['amount'], value['precision'], value['nai']]

    if isinstance(value, str):
        raw_amount, unit = value.split(' ')
        if unit == 'SBD':
            unit = 'HBD'
        elif unit == 'STEEM':
            unit = 'HIVE'
        dec_amount = decimal.Decimal(raw_amount)

    elif isinstance(value, list):
        satoshis, precision, nai = value
        dec_amount = decimal.Decimal(satoshis) / (10**precision)
        assert nai in NAI_MAP, f"unknown NAI {nai}; expected {expected_unit or '(any)'}"
        unit = NAI_MAP[nai]

    else:
        raise Exception(f"invalid input amount {repr(value)}")

    if expected_unit:
        # FIXME to be uncommented when payout collection will be corrected
        #        assert unit == expected_unit, "Unexpected unit: %s" % unit
        return dec_amount

    return (dec_amount, unit)


def amount(string):
    """Parse a steemd asset-amount as a Decimal(). Discard asset type."""
    return parse_amount(string)[0]


def legacy_amount(value):
    """Get a pre-appbase-style amount string given a (numeric, asset-str)."""
    if isinstance(value, str):
        return value  # already legacy
    amt, asset = parse_amount(value)
    prec = {'HBD': 3, 'HIVE': 3, 'VESTS': 6}[asset]
    tmpl = "%%.%df %%s" % prec
    return tmpl % (amt, asset)


def block_num(block):
    """Given a block object, returns the block number."""
    return int(block['block_id'][:8], base=16)


def block_date(block):
    """Parse block timestamp into datetime object."""
    return parse_time(block['timestamp'])


def parse_time(block_time):
    """Convert chain date into datetime object."""
    return datetime.strptime(block_time, '%Y-%m-%dT%H:%M:%S')


def utc_timestamp(date):
    """Convert datetime to UTC unix timestamp."""
    return date.replace(tzinfo=utc).timestamp()


def load_json_key(obj, key):
    """Given a dict, parse JSON in `key`. Blank dict on failure."""
    if not obj[key]:
        return {}
    ret = {}
    try:
        ret = json.loads(obj[key])
    except Exception:
        return {}
    return ret


def trunc(string, maxlen):
    """Truncate a string, with a 3-char penalty if maxlen exceeded."""
    if string:
        string = string.strip()
        if len(string) > maxlen:
            string = string[0 : (maxlen - 3)] + '...'
    return string


def secs_to_str(secs):
    """Given number of seconds returns, e.g., `02h 29m 39s`"""
    units = (('s', 60), ('m', 60), ('h', 24), ('d', 7))
    out = []
    rem = secs
    for (unit, cycle) in units:
        out.append((rem % cycle, unit))
        rem = int(rem / cycle)
        if not rem:
            break
    if rem:  # leftover = weeks
        out.append((rem, 'w'))
    return ' '.join(["%02d%s" % tup for tup in out[::-1]])


def rep_log10(rep):
    """Convert raw steemd rep into a UI-ready value centered at 25."""

    def _log10(string):
        leading_digits = int(string[0:4])
        log = math.log10(leading_digits) + 0.00000001
        num = len(string) - 1
        return num + (log - int(log))

    rep = str(rep)
    if rep == "0":
        return 25

    sign = -1 if rep[0] == '-' else 1
    if sign < 0:
        rep = rep[1:]

    out = _log10(rep)
    out = max(out - 9, 0) * sign  # @ -9, $1 earned is approx magnitude 1
    out = (out * 9) + 25  # 9 points per magnitude. center at 25
    return float(round(out, 2))


def rep_to_raw(rep):
    """Convert a UI-ready rep score back into its approx raw value."""
    if not isinstance(rep, (str, float, int)):
        return 0
    if float(rep) == 25:
        return 0
    rep = float(rep) - 25
    rep = rep / 9
    sign = 1 if rep >= 0 else -1
    rep = abs(rep) + 9
    return int(sign * pow(10, rep))


def strtobool(val):
    """Convert a booleany str to a bool.

    True values are 'y', 'yes', 't', 'true', 'on', and '1'; false values
    are 'n', 'no', 'f', 'false', 'off', and '0'.  Raises ValueError if
    'val' is anything else.
    """
    val = val.lower()
    if val in ('y', 'yes', 't', 'true', 'on', '1'):
        return True
    elif val in ('n', 'no', 'f', 'false', 'off', '0'):
        return False
    else:
        raise ValueError(f"not booleany: {val!r}")


def int_log_level(str_log_level):
    """Get `logger`s internal int level from config string."""
    if not str_log_level:
        raise ValueError('Empty log level passed')
    log_level = getattr(logging, str_log_level.upper(), None)
    if not isinstance(log_level, int):
        raise ValueError(f'Invalid log level: {str_log_level}')
    return log_level

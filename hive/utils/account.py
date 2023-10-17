"""Methods for normalizing/sanitizing hived account data."""

import ujson as json
import re
from hive.utils.normalize import trunc



def get_profile_str(account):
    _posting_json_metadata = ""
    _json_metadata = ""

    if account is not None:
        if 'posting_json_metadata' in account:
            _posting_json_metadata = account['posting_json_metadata']
        if 'json_metadata' in account:
            _json_metadata = account['json_metadata']

    return (_posting_json_metadata, _json_metadata)


def get_db_profile(posting_json_metadata, json_metadata):
    prof = {}
    json_metadata_is_read = False

    # `posting_json_metadata` should dominate, so at the start is necessary to load `posting_json_metadata`
    # We can skip `posting_json_metadata` loading when it doesn't exist or content doesn't make any sense(f.e. '' or '{}' )
    try:
        if posting_json_metadata is None or len(posting_json_metadata) <= 2:
            json_metadata_is_read = True
            prof = json.loads(json_metadata)['profile']
        else:
            prof = json.loads(posting_json_metadata)['profile']
    except Exception:
        try:
            if not json_metadata_is_read:
                prof = json.loads(json_metadata)['profile']
        except Exception:
            prof = {}

    return prof


def get_profile(account):
    prof = {}

    try:
        # read from posting_json_metadata, if version==2
        prof = json.loads(account['posting_json_metadata'])['profile']
        assert isinstance(prof, dict)
        assert 'version' in prof and prof['version'] == 2
    except Exception:
        try:
            # fallback to json_metadata
            prof = json.loads(account['json_metadata'])['profile']
            assert isinstance(prof, dict)
        except Exception:
            prof = {}

    return prof


def process_profile(prof):
    """Returns profile data."""

    name = str(prof['name']) if 'name' in prof else None
    about = str(prof['about']) if 'about' in prof else None
    location = str(prof['location']) if 'location' in prof else None
    website = str(prof['website']) if 'website' in prof else None
    profile_image = str(prof['profile_image']) if 'profile_image' in prof else None
    cover_image = str(prof['cover_image']) if 'cover_image' in prof else None
    blacklist_description = str(prof['blacklist_description']) if 'blacklist_description' in prof else None
    muted_list_description = str(prof['muted_list_description']) if 'muted_list_description' in prof else None

    name = _char_police(name)
    about = _char_police(about)
    location = _char_police(location)
    blacklist_description = _char_police(blacklist_description)
    muted_list_description = _char_police(muted_list_description)

    name = trunc(name, 20)
    about = trunc(about, 160)
    location = trunc(location, 30)
    blacklist_description = trunc(blacklist_description, 256)
    muted_list_description = trunc(muted_list_description, 256)

    if name and name[0:1] == '@':
        name = None
    if website and len(website) > 100:
        website = None
    if website and not _valid_url_proto(website):
        website = 'http://' + website

    if profile_image and not _valid_url_proto(profile_image):
        profile_image = None
    if cover_image and not _valid_url_proto(cover_image):
        cover_image = None
    if profile_image and len(profile_image) > 1024:
        profile_image = None
    if cover_image and len(cover_image) > 1024:
        cover_image = None

    return dict(
        name=name or '',
        about=about or '',
        location=location or '',
        website=website or '',
        profile_image=profile_image or '',
        cover_image=cover_image or '',
        blacklist_description=blacklist_description or '',
        muted_list_description=muted_list_description or '',
    )


def safe_db_profile_metadata(posting_json_metadata, json_metadata):
    prof = get_db_profile(posting_json_metadata, json_metadata)
    return process_profile(prof)


def safe_profile_metadata(account):
    prof = get_profile(account)
    return process_profile(prof)


def _valid_url_proto(url):
    assert url
    return url[0:7] == 'http://' or url[0:8] == 'https://'


def _char_police(string):
    """If a string has bad chars, ignore it.

    Unclear how a NUL would get in profile data,
    but Postgres does not allow them in strings.
    """
    if not string:
        return None
    if string.find('\x00') > -1:
        return None
    return string

def validate_account_name(value):
    assert isinstance(value, str), 'account name must be a string'
    assert value, "Account name should not be empty."

    length = len(value)
    assert length >= 3, "Account name should be longer."
    assert length <= 16, "Account name should be shorter."

    segments = value.split(".")
    for label in segments:
        assert re.match(r"^[a-z]", label), "Each account segment should start with a letter."
        assert re.match(r"^[a-z0-9-]*$", label), "Each account segment should have only letters, digits, or dashes."
        assert re.search(r"[a-z0-9]$", label), "Each account segment should end with a letter or digit."
        assert len(label) >= 3, "Each account segment should be longer."

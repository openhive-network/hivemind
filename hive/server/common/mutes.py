"""List of muted accounts for server process."""

import logging
from time import perf_counter as perf
from urllib.request import urlopen, Request
from hive.db.adapter import Db

log = logging.getLogger(__name__)

GET_BLACKLISTED_ACCOUNTS_SQL = """
WITH blacklisted_users AS (
    SELECT following, 'my_blacklist' AS source FROM hive_follows WHERE follower =
        (SELECT id FROM hive_accounts WHERE name = :observer )
    AND blacklisted
    UNION ALL
    SELECT following, 'my_followed_blacklists' AS source FROM hive_follows WHERE follower IN
    (SELECT following FROM hive_follows WHERE follower =
        (SELECT id FROM hive_accounts WHERE name = :observer )
    AND follow_blacklists) AND blacklisted
    UNION ALL
    SELECT following, 'my_muted' AS source FROM hive_follows WHERE follower =
        (SELECT id FROM hive_accounts WHERE name = :observer )
    AND state = 2
    UNION ALL
    SELECT following, 'my_followed_mutes' AS source FROM hive_follows WHERE follower IN
    (SELECT following FROM hive_follows WHERE follower =
        (SELECT id FROM hive_accounts WHERE name = :observer )
    AND follow_muted) AND state = 2
)
SELECT following, source FROM blacklisted_users
"""

def _read_url(url):
    req = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    return urlopen(req).read()

class Mutes:
    """Singleton tracking muted accounts."""

    _instance = None
    url = None
    accounts = set() # list/irredeemables
    blist = set() # list/any-blacklist
    blist_map = dict() # cached account-list map
    fetched = None
    all_accounts = dict()

    @classmethod
    def instance(cls):
        """Get the shared instance."""
        assert cls._instance, 'set_shared_instance was never called'
        return cls._instance

    @classmethod
    def set_shared_instance(cls, instance):
        """Set the global/shared instance."""
        cls._instance = instance

    def __init__(self, url, blacklist_api_url):
        """Initialize a muted account list by loading from URL"""
        self.url = url
        self.blacklist_api_url = blacklist_api_url
        if url:
            self.load()

    def load(self):
        """Reload all accounts from irredeemables endpoint and global lists."""
        self.all_accounts.clear()
        sql = "select id, name from hive_accounts"
        db = Db.instance()
        sql_result = db.query_all(sql)
        for row in sql_result:
            self.all_accounts[row['id']] = row['name']
        self.fetched = perf()

    @classmethod
    def all(cls):
        """Return the set of all muted accounts from singleton instance."""
        return cls.instance().accounts

    @classmethod
    async def get_blacklists_for_observer(cls, observer=None, context=None):
        """ fetch the list of users that the observer has blacklisted """
        if not observer or not context:
            return {}

        if cls.instance().fetched and (perf() - cls.instance().fetched) > 3600:
            cls.instance().load()

        blacklisted_users = {}

        db = context['db']
        sql = GET_BLACKLISTED_ACCOUNTS_SQL
        sql_result = await db.query_all(sql, observer=observer)
        for row in sql_result:
            account_name = cls.all_accounts[row['following']]
            if account_name not in blacklisted_users:
                blacklisted_users[account_name] = []
            blacklisted_users[account_name].append(row['source'])
        return blacklisted_users

    @classmethod
    def lists(cls, name, rep):
        """Return blacklists the account belongs to."""
        # TODO: Refactor/remove this method
        return[]

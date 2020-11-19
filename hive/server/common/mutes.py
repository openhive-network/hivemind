"""List of muted accounts for server process."""

import logging
from time import perf_counter as perf
from urllib.request import urlopen, Request
from hive.db.adapter import Db

log = logging.getLogger(__name__)

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
    async def get_blacklisted_for_observer(cls, observer, context, flags=1+2+4+8):
        """ fetch the list of users that the observer has blacklisted
            flags allow filtering the query:
            1 - accounts blacklisted by observer
            2 - accounts blacklisted by observer's follow_blacklist lists
            4 - accounts muted by observer
            8 - accounts muted by observer's follow_mutes lists
            by default all flags are set
        """
        if not observer or not context:
            return {}

        if cls.instance().fetched and (perf() - cls.instance().fetched) > 3600:
            cls.instance().load()

        blacklisted_users = {}

        db = context['db']
        sql = "SELECT * FROM mutes_get_blacklisted_for_observer( (:observer)::VARCHAR, (:flags)::INTEGER )"
        sql_result = await db.query_all(sql, observer=observer, flags=flags)
        for row in sql_result:
            account_name = row['account']
            if account_name not in blacklisted_users:
                blacklisted_users[account_name] = ([], [])
            if row['is_blacklisted']:
                blacklisted_users[account_name][0].append(row['source'])
            else: # muted
                blacklisted_users[account_name][1].append(row['source'])
        return blacklisted_users

    @classmethod
    async def get_blacklists_for_observer(cls, observer, context, follow_blacklist = True, follow_muted = True):
        """ fetch the list of accounts that are followed by observer through follow_blacklist/follow_muted """
        if not observer or not context:
            return {}

        db = context['db']
        sql = "SELECT * FROM mutes_get_blacklists_for_observer( (:observer)::VARCHAR, (:fb)::BOOLEAN, (:fm)::BOOLEAN )"
        return await db.query_all(sql, observer=observer, fb=follow_blacklist, fm=follow_muted)

    @classmethod
    def lists(cls, name, rep):
        """Return blacklists the account belongs to."""
        # TODO: Refactor/remove this method
        return[]

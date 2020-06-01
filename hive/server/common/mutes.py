"""List of muted accounts for server process."""

import logging
from time import perf_counter as perf
from urllib.request import urlopen, Request
import ujson as json
from hive.server.common.helpers import valid_account

log = logging.getLogger(__name__)

GET_BLACKLISTED_ACCOUNTS = """
with blacklisted_users as (select following, 'my_blacklist' as source from hive_follows where follower = 
    (select id from hive_accounts where name = 'jes2850' ) and blacklisted
union all
select following, 'my_followed_blacklists' as source from hive_follows where follower in (select following from hive_follows where follower = 
    (select id from hive_accounts where name = 'jes2850') and follow_blacklists))

select hive_accounts.name, blacklisted_users.source from hive_accounts join blacklisted_users on (hive_accounts.id = blacklisted_users.following)
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
        return
        self.accounts = set(_read_url(self.url).decode('utf8').split())
        jsn = _read_url(self.blacklist_api_url + "/blacklists")
        self.blist = set(json.loads(jsn))
        log.warning("%d muted, %d blacklisted", len(self.accounts), len(self.blist))
        self.fetched = perf()

    @classmethod
    def all(cls, observer=None, context=None):
        """Return the set of all muted accounts from singleton instance."""
        if not observer:
            return cls.instance().accounts

        if not context:
            return cls.instance().accounts

        valid_account(observer)

        db = context['db']
        sql = GET_BLACKLISTED_ACCOUNTS
        sql_result = db.query_all(sql, observer=observer)

        names = set()
        for row in sql_result:
            names.add(row['name'])
        return names

    @classmethod
    def lists(cls, name, rep, observer=None, context=None):
        """Return blacklists the account belongs to."""
        return[]
        assert name
        inst = cls.instance()

        if observer and context:
            blacklists_for_user = []
            valid_account(observer)
            db = context['db']

            sql = GET_BLACKLISTED_ACCOUNTS
            sql_result = db.query_all(sql, observer=observer)
            for row in sql_result:
                blacklists_for_user.append(row['source'])

            if int(rep) < 1:
                blacklists_for_user.append('reputation-0')
            if int(rep) == 1:

                blacklists_for_user.append('reputation-1')

            return blacklists_for_user

        # update hourly
        if perf() - inst.fetched > 3600:
            inst.load()

        if name not in inst.blist and name not in inst.accounts:
            if name in inst.blist_map: #this user was blacklisted, but has been removed from the blacklists since the last check
                inst.blist_map.pop(name)    #so just pop them from the cache
            return []
        else:   # user is on at least 1 list
            blacklists_for_user = []
            if name not in inst.blist_map:  #user has been added to a blacklist since the last check so figure out what lists they belong to
                if name in inst.blist: #blacklisted accounts
                    url = "%s/user/%s" % (inst.blacklist_api_url, name)
                    lists = json.loads(_read_url(url))
                    blacklists_for_user.extend(lists['blacklisted'])

                if name in inst.accounts:   #muted accounts
                    if 'irredeemables' not in blacklists_for_user:
                        blacklists_for_user.append('irredeemables')

            if int(rep) < 1:
                blacklists_for_user.append('reputation-0')  #bad reputation
            if int(rep) == 1:
                blacklists_for_user.append('reputation-1') #bad reputation

            inst.blist_map[name] = blacklists_for_user
            return inst.blist_map[name]

"""List of muted accounts for server process."""
from hive.conf import SCHEMA_NAME


class Mutes:
    """Singleton tracking muted accounts."""

    @classmethod
    async def get_blacklisted_for_observer(cls, observer, context, flags=1 + 2 + 4 + 8):
        """fetch the list of users that the observer has blacklisted
        flags allow filtering the query:
        1 - accounts blacklisted by observer
        2 - accounts blacklisted by observer's follow_blacklist lists
        4 - accounts muted by observer
        8 - accounts muted by observer's follow_mutes lists
        by default all flags are set
        """
        if not observer or not context:
            return {}

        blacklisted_users = {}

        db = context['db']
        sql = (
            f"SELECT * FROM {SCHEMA_NAME}.mutes_get_blacklisted_for_observer( (:observer)::VARCHAR, (:flags)::INTEGER )"
        )
        sql_result = await db.query_all(sql, observer=observer, flags=flags)
        for row in sql_result:
            account_name = row['account']
            if account_name not in blacklisted_users:
                blacklisted_users[account_name] = ([], [])
            if row['is_blacklisted']:
                blacklisted_users[account_name][0].append(row['source'])
            else:  # muted
                blacklisted_users[account_name][1].append(row['source'])
        return blacklisted_users

    @classmethod
    async def get_blacklists_for_observer(cls, observer, context, follow_blacklist=True, follow_muted=True):
        """fetch the list of accounts that are followed by observer through follow_blacklist/follow_muted"""
        if not observer or not context:
            return {}

        db = context['db']
        sql = f"SELECT * FROM {SCHEMA_NAME}.mutes_get_blacklists_for_observer( (:observer)::VARCHAR, (:fb)::BOOLEAN, (:fm)::BOOLEAN )"
        return await db.query_all(sql, observer=observer, fb=follow_blacklist, fm=follow_muted)

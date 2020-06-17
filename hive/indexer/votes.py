""" Votes indexing and processing """

import logging

from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

class Votes:
    """ Class for managing posts votes """
    @classmethod
    def get_id(cls, voter, author, permlink):
        """ Check if vote exists, if yes return its id, else return None """
        sql = """
            SELECT 
                hv.id 
            FROM 
                hive_votes hv
            INNER JOIN hive_accounts ha_v ON (ha_v.id = hv.voter_id)
            INNER JOIN hive_accounts ha_a ON (ha_a.id = hv.author_id)
            INNER JOIN hive_permlink_data hpd ON (hpd.id = hv.permlink_id)
            WHERE ha_v.name = :voter AND ha_a.name = :author AND hpd.permlink = :permlink
        """
        ret = DB.query_row(sql, voter=voter, author=author, permlink=permlink)
        return None if ret is None else int(ret.id)

    @classmethod
    def get_vote_count(cls, author, permlink):
        """ Get vote count for given post """
        sql = """
            SELECT 
                count(hv.id)
            FROM 
                hive_votes hv
             INNER JOIN hive_accounts ha_a ON (ha_a.id = hv.author_id)
            INNER JOIN hive_permlink_data hpd ON (hpd.id = hv.permlink_id)
            WHERE ha_a.name = :author AND hpd.permlink = :permlink
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(ret.count)

    @classmethod
    def vote_op(cls, vop, date):
        """ Process vote_operation """
        voter = vop['op']['value']['voter']
        author = vop['op']['value']['author']
        permlink = vop['op']['value']['permlink']

        vote_id = cls.get_id(voter, author, permlink)
        # no vote so create new
        if vote_id is None:
            cls._insert(vop, date)
        else:
            cls._update(vote_id, vop, date)

    @classmethod
    def _insert(cls, vop, date):
        """ Insert new vote """
        voter = vop['op']['value']['voter']
        author = vop['op']['value']['author']
        permlink = vop['op']['value']['permlink']
        vote_percent = vop['op']['value']['vote_percent']
        sql = """
            INSERT INTO 
                hive_votes (voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update) 
            VALUES (
                (SELECT id FROM hive_accounts WHERE name = :voter),
                (SELECT id FROM hive_accounts WHERE name = :author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :permlink),
                :weight,
                :rshares,
                :vote_percent,
                :last_update
            )"""
        weight = vop['op']['value']['weight']
        rshares = vop['op']['value']['rshares']
        DB.query(sql, voter=voter, author=author, permlink=permlink, weight=weight, rshares=rshares,
                 vote_percent=vote_percent, last_update=date)

    @classmethod
    def _update(cls, vote_id, vop, date):
        """ Update existing vote """
        vote_percent = vop['op']['value']['vote_percent']
        sql = """
            UPDATE 
                hive_votes 
            SET
                weight = :weight,
                rshares = :rshares,
                vote_percent = :vote_percent,
                last_update = :last_update,
                num_changes = (SELECT num_changes FROM hive_votes WHERE id = :id)::int + 1
            WHERE id = :id
        """
        weight = vop['op']['value']['weight']
        rshares = vop['op']['value']['rshares']
        DB.query(sql, weight=weight, rshares=rshares, vote_percent=vote_percent, last_update=date,
                 id=vote_id)

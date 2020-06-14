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
        return None if ret is None else ret.id

    @classmethod
    def vote_op(cls, op, date):
        """ Process vote_operation """
        voter = op['voter']
        author = op['author']
        permlink = op['permlink']

        vote_id = cls.get_id(voter, author, permlink)
        # no vote so create new
        if vote_id is None:
            cls._insert(op, date)
        else:
            cls._update(vote_id, op, date)

    @classmethod
    def _insert(cls, op, date):
        """ Insert new vote """
        voter = op['voter']
        author = op['author']
        permlink = op['permlink']
        vote_percent = op['weight']
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
        # [DK] calculation of those is quite complicated, must think
        weight = 0
        rshares = 0
        DB.query(sql, voter=voter, author=author, permlink=permlink, weight=weight, rshares=rshares,
                 vote_percent=vote_percent, last_update=date)

    @classmethod
    def _update(cls, vote_id, op, date):
        """ Update existing vote """
        vote_percent = op['weight']
        sql = """
            UPDATE 
                hive_votes 
            SET
                weight = :weight,
                rshares = :rshares,
                vote_percent = :vote_percent,
                last_update = :last_update,
                num_changes = (SELECT num_changes FROM hive_votes WHERE id = :id) + 1
            WHERE id = :id
        """
        # [DK] calculation of those is quite complicated, must think
        weight = 0
        rshares = 0
        DB.query(sql, weight=weight, rshares=rshares, vote_percent=vote_percent, last_update=date,
                 id=vote_id)


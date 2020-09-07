""" Votes indexing and processing """

import logging

from hive.db.db_state import DbState
from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

class Votes:
    """ Class for managing posts votes """
    _votes_data = {}

    inside_flush = False

    @classmethod
    def vote_op(cls, vote_operation, date):
        """ Process vote_operation """
        voter     = vote_operation['voter']
        author    = vote_operation['author']
        permlink  = vote_operation['permlink']
        weight    = vote_operation['weight']
        block_num = vote_operation['block_num']

        if cls.inside_flush:
            log.exception("Adding new vote-info into '_votes_data' dict")
            raise RuntimeError("Fatal error")

        key = "{}/{}/{}".format(voter, author, permlink)

        if key in cls._votes_data:
            cls._votes_data[key]["vote_percent"] = weight
            cls._votes_data[key]["last_update"] = date
        else:
            cls._votes_data[key] = dict(voter=voter,
                                        author=author,
                                        permlink=permlink,
                                        vote_percent=weight,
                                        weight=0,
                                        rshares=0,
                                        last_update=date,
                                        is_effective=False,
                                        block_num=block_num)

    @classmethod
    def effective_comment_vote_op(cls, vop):
        """ Process effective_comment_vote_operation """

        key = "{}/{}/{}".format(vop['voter'], vop['author'], vop['permlink'])

        if key in cls._votes_data:
          cls._votes_data[key]["weight"]       = vop["weight"]
          cls._votes_data[key]["rshares"]      = vop["rshares"]
          cls._votes_data[key]["is_effective"] = True
          cls._votes_data[key]["block_num"]    = vop['block_num']
        else:
            cls._votes_data[key] = dict(voter=vop['voter'],
                                        author=vop['author'],
                                        permlink=vop['permlink'],
                                        vote_percent=0,
                                        weight=vop["weight"],
                                        rshares=vop["rshares"],
                                        last_update='1970-01-01 00:00:00',
                                        is_effective=True,
                                        block_num=vop['block_num'])
    @classmethod
    def flush(cls):
        """ Flush vote data from cache to database """
        cls.inside_flush = True
        n = 0
        if cls._votes_data:
            sql = """
                INSERT INTO hive_votes
                (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num, is_effective)

                SELECT hp.id as post_id, ha_v.id as voter_id, ha_a.id as author_id, hpd_p.id as permlink_id,
                t.weight, t.rshares, t.vote_percent, t.last_update, t.block_num, t.is_effective
                FROM
                (
                VALUES
                  -- voter, author, permlink, weight, rshares, vote_percent, last_update, block_num, is_effective
                  {}
                ) AS T(voter, author, permlink, weight, rshares, vote_percent, last_update, block_num, is_effective)
                INNER JOIN hive_accounts ha_v ON ha_v.name = t.voter
                INNER JOIN hive_accounts ha_a ON ha_a.name = t.author
                INNER JOIN hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
                INNER JOIN hive_posts hp ON hp.author_id = ha_a.id AND hp.permlink_id = hpd_p.id
                WHERE hp.counter_deleted = 0
                ON CONFLICT ON CONSTRAINT hive_votes_pk DO
                UPDATE
                  SET
                    weight = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.weight ELSE hive_votes.weight END,
                    rshares = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.rshares ELSE hive_votes.rshares END,
                    vote_percent = EXCLUDED.vote_percent,
                    last_update = EXCLUDED.last_update,
                    num_changes = hive_votes.num_changes + 1
                  WHERE hive_votes.voter_id = EXCLUDED.voter_id and hive_votes.author_id = EXCLUDED.author_id and hive_votes.permlink_id = EXCLUDED.permlink_id;
                """
            # WHERE clause above seems superfluous (and works all the same without it, at least up to 5mln)

            values = []
            values_limit = 1000

            for _, vd in cls._votes_data.items():
                values.append("('{}', '{}', '{}', {}, {}, {}, '{}'::timestamp, {}, {})".format(
                    vd['voter'], vd['author'], vd['permlink'], vd['weight'], vd['rshares'],
                    vd['vote_percent'], vd['last_update'], vd['block_num'], vd['is_effective']))

                if len(values) >= values_limit:
                    values_str = ','.join(values)
                    actual_query = sql.format(values_str)
                    DB.query(actual_query)
                    values.clear()

            if len(values) > 0:
                values_str = ','.join(values)
                actual_query = sql.format(values_str)
                DB.query(actual_query)
                values.clear()

            n = len(cls._votes_data)
            cls._votes_data.clear()
        cls.inside_flush = False
        return n

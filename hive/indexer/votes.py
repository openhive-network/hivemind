""" Votes indexing and processing """

import logging

from hive.db.adapter import Db

log = logging.getLogger(__name__)
DB = Db.instance()

class Votes:
    """ Class for managing posts votes """
    _votes_data = {}

    @classmethod
    def get_vote_count(cls, author, permlink):
        """ Get vote count for given post """
        sql = """
            SELECT count(1)
            FROM hive_votes_accounts_permlinks_view hv
            WHERE hv.author = :author AND hv.permlink = :permlink
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(ret.count)

    @classmethod
    def get_upvote_count(cls, author, permlink):
        """ Get vote count for given post """
        sql = """
            SELECT count(1)
            FROM hive_votes_accounts_permlinks_view hv
            WHERE hv.author = :author AND hv.permlink = :permlink
                  AND hv.percent > 0
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(ret.count)

    @classmethod
    def get_downvote_count(cls, author, permlink):
        """ Get vote count for given post """
        sql = """
            SELECT count(1)
            FROM hive_votes_accounts_permlinks_view hv
            WHERE hv.author = :author AND hv.permlink = :permlink
                  AND hv.percent < 0
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(ret.count)

    inside_flush = False

    @classmethod
    def vote_op(cls, vop):
        """ Process vote_operation """
        voter = vop['voter']
        author = vop['author']
        permlink = vop['permlink']

        if(cls.inside_flush):
            log.info("Adding new vote-info into '_votes_data' dict")
            raise "Fatal error"

        key = voter + "/" + author + "/" + permlink

        cls._votes_data[key] = dict(voter=voter,
                                    author=author,
                                    permlink=permlink,
                                    vote_percent=0,
                                    weight=0,
                                    rshares=0,
                                    last_update="1969-12-31T23:59:59")

    @classmethod
    def effective_comment_vote_op(cls, vop, date):
        """ Process effective_comment_vote_operation """
        voter = vop['voter']
        author = vop['author']
        permlink = vop['permlink']

        if(cls.inside_flush):
            log.info("Updating data in '_votes_data' using effective comment")
            raise "Fatal error"

        key = voter + "/" + author + "/" + permlink
        assert key in cls._votes_data

        log.info( "xx {}".format(vop) )

        cls._votes_data[key]["vote_percent"]  = vop["vote_percent"]
        cls._votes_data[key]["weight"]        = vop["weight"]
        cls._votes_data[key]["rshares"]       = vop["rshares"]
        cls._votes_data[key]["last_update"]   = date

    @classmethod
    def flush(cls):
        """ Flush vote data from cache to database """
        cls.inside_flush = True
        if cls._votes_data:
            sql = """
                    INSERT INTO hive_votes
                    (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update) 
                    select data_source.post_id, data_source.voter_id, data_source.author_id, data_source.permlink_id, data_source.weight, data_source.rshares, data_source.vote_percent, data_source.last_update
                    from 
                    (
                    SELECT hp.id as post_id, ha_v.id as voter_id, ha_a.id as author_id, hpd_p.id as permlink_id, t.weight, t.rshares, t.vote_percent, t.last_update
                    from
                    (
                    VALUES
                    --   voter, author, permlink, weight, rshares, vote_percent, last_update
                      {}
                    ) AS T(voter, author, permlink, weight, rshares, vote_percent, last_update)
                    INNER JOIN hive_accounts ha_v ON ha_v.name = t.voter
                    INNER JOIN hive_accounts ha_a ON ha_a.name = t.author
                    INNER JOIN hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
                    INNER JOIN hive_posts hp ON hp.author_id = ha_a.id AND hp.permlink_id = hpd_p.id  
                    ) as data_source(post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update)
                    ON CONFLICT ON CONSTRAINT hive_votes_ux1 DO
                      UPDATE
                        SET
                          weight = EXCLUDED.weight,
                          rshares = EXCLUDED.rshares,
                          vote_percent = EXCLUDED.vote_percent,
                          last_update = EXCLUDED.last_update,
                          num_changes = hive_votes.num_changes + 1
                      WHERE hive_votes.voter_id = EXCLUDED.voter_id and hive_votes.author_id = EXCLUDED.author_id and hive_votes.permlink_id = EXCLUDED.permlink_id;
                      """

            values = []
            values_limit = 1000

            for _, vd in cls._votes_data.items():
                values.append("('{}', '{}', '{}', {}, {}, {}, '{}'::timestamp)".format(
                    vd['voter'], vd['author'], vd['permlink'], vd['weight'], vd['rshares'], vd['vote_percent'], vd['last_update']))

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

            cls._votes_data.clear()
        cls.inside_flush = False

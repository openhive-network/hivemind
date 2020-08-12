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

    @classmethod
    def get_total_vote_weight(cls, author, permlink):
        """ Get total vote weight for selected post """
        sql = """
            SELECT 
                sum(weight)
            FROM 
                hive_votes_accounts_permlinks_view hv
            WHERE 
                hv.author = :author AND
                hv.permlink = :permlink
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(0 if ret.sum is None else ret.sum)

    @classmethod
    def get_total_vote_rshares(cls, author, permlink):
        """ Get total vote rshares for selected post """
        sql = """
            SELECT 
                sum(rshares)
            FROM 
                hive_votes_accounts_permlinks_view hv
            WHERE 
                hv.author = :author AND
                hv.permlink = :permlink
        """
        ret = DB.query_row(sql, author=author, permlink=permlink)
        return 0 if ret is None else int(0 if ret.sum is None else ret.sum)

    inside_flush = False

    @classmethod
    def vote_op(cls, vote_operation, date):
        """ Process vote_operation """
        voter     = vote_operation['voter']
        author    = vote_operation['author']
        permlink  = vote_operation['permlink']
        weight    = vote_operation['weight']

        if cls.inside_flush:
            log.exception("Adding new vote-info into '_votes_data' dict")
            raise RuntimeError("Fatal error")

        basic_key = "{}/{}".format(author, permlink)
        key = voter + "/" + author + "/" + permlink

        if basic_key not in cls._votes_data:
          cls._votes_data[basic_key] = {}

        if key in cls._votes_data[basic_key]:
            cls._votes_data[basic_key][key]["vote_percent"] = weight
            cls._votes_data[basic_key][key]["last_update"] = date
        else:
            cls._votes_data[basic_key][key] = dict(voter=voter,
                                                   author=author,
                                                   permlink=permlink,
                                                   vote_percent=weight,
                                                   weight=0,
                                                   rshares=0,
                                                   last_update=date,
                                                   is_effective=False)

    @classmethod
    def effective_comment_vote_op(cls, key, vop):
        """ Process effective_comment_vote_operation """

        if cls.inside_flush:
            log.exception("Updating data in '_votes_data' using effective comment")
            raise RuntimeError("Fatal error")

        basic_key = vop["basic_key"]

        assert basic_key in cls._votes_data
        assert key in cls._votes_data[basic_key]

        cls._votes_data[basic_key][key]["weight"]       = vop["op"]["weight"]
        cls._votes_data[basic_key][key]["rshares"]      = vop["op"]["rshares"]
        cls._votes_data[basic_key][key]["is_effective"] = True

    @classmethod
    def write_data_into_db_before_post_deleting(cls, key):
      if key not in cls._votes_data:
        return

      _tmp_data = {}

      #Extract data for given key
      _tmp_data[key] = cls._votes_data[key]

      #Save into database
      cls.flush_from_source(_tmp_data)

      #Remove from original dictionary
      del cls._votes_data[key]

    @classmethod
    def flush_from_source(cls, source):
        """ Flush vote data from cache to database """
        cls.inside_flush = True
        if source:
            sql = """
                INSERT INTO hive_votes
                (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update) 
                SELECT hp.id as post_id, ha_v.id as voter_id, ha_a.id as author_id, hpd_p.id as permlink_id, t.weight, t.rshares, t.vote_percent, t.last_update
                FROM
                (
                VALUES
                  -- voter, author, permlink, weight, rshares, vote_percent, last_update
                  {}
                ) AS T(voter, author, permlink, weight, rshares, vote_percent, last_update)
                INNER JOIN hive_accounts ha_v ON ha_v.name = t.voter
                INNER JOIN hive_accounts ha_a ON ha_a.name = t.author
                INNER JOIN hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
                INNER JOIN hive_posts hp ON hp.author_id = ha_a.id AND hp.permlink_id = hpd_p.id
                ON CONFLICT ON CONSTRAINT hive_votes_ux1 DO
                UPDATE
                  SET
                    weight = {}.weight,
                    rshares = {}.rshares,
                    vote_percent = EXCLUDED.vote_percent,
                    last_update = EXCLUDED.last_update,
                    num_changes = hive_votes.num_changes + 1
                  WHERE hive_votes.voter_id = EXCLUDED.voter_id and hive_votes.author_id = EXCLUDED.author_id and hive_votes.permlink_id = EXCLUDED.permlink_id;
                """
            # WHERE clause above seems superfluous (and works all the same without it, at least up to 5mln)

            values_skip = []
            values_override = []
            values_limit = 1000

            for key, value in source.items():
              for _, vd in value.items():
                  values = None
                  on_conflict_data_source = None

                  if vd['is_effective']:
                      values = values_override
                      on_conflict_data_source = 'EXCLUDED'
                  else:
                      values = values_skip
                      on_conflict_data_source = 'hive_votes'

                  values.append("('{}', '{}', '{}', {}, {}, {}, '{}'::timestamp)".format(
                      vd['voter'], vd['author'], vd['permlink'], vd['weight'], vd['rshares'], vd['vote_percent'], vd['last_update']))

                  if len(values) >= values_limit:
                      values_str = ','.join(values)
                      actual_query = sql.format(values_str,on_conflict_data_source,on_conflict_data_source)
                      DB.query(actual_query)
                      values.clear()

            if len(values_skip) > 0:
                values_str = ','.join(values_skip)
                actual_query = sql.format(values_str, 'hive_votes', 'hive_votes')
                DB.query(actual_query)
                values_skip.clear()
            if len(values_override) > 0:
                values_str = ','.join(values_override)
                actual_query = sql.format(values_str, 'EXCLUDED', 'EXCLUDED')
                DB.query(actual_query)
                values_override.clear()

            source.clear()
        cls.inside_flush = False

    @classmethod
    def flush(cls):
      cls.flush_from_source(cls._votes_data)

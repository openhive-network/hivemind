DROP FUNCTION IF EXISTS hivemind_app.date_diff() CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.date_diff (units VARCHAR(30), start_t TIMESTAMP, end_t TIMESTAMP)
  RETURNS INT AS $$
DECLARE
  diff_interval INTERVAL;
  diff INT = 0;
  years_diff INT = 0;
BEGIN
  IF units IN ('yy', 'yyyy', 'year', 'mm', 'm', 'month') THEN
    years_diff = DATE_PART('year', end_t) - DATE_PART('year', start_t);
    IF units IN ('yy', 'yyyy', 'year') THEN
      -- SQL Server does not count full years passed (only difference between year parts)
      RETURN years_diff;
    ELSE
      -- If end month is less than start month it will subtracted
      RETURN years_diff * 12 + (DATE_PART('month', end_t) - DATE_PART('month', start_t));
    END IF;
  END IF;
  -- Minus operator returns interval 'DDD days HH:MI:SS'
  diff_interval = end_t - start_t;
  diff = diff + DATE_PART('day', diff_interval);
  IF units IN ('wk', 'ww', 'week') THEN
    diff = diff/7;
    RETURN diff;
  END IF;
  IF units IN ('dd', 'd', 'day') THEN
    RETURN diff;
  END IF;
  diff = diff * 24 + DATE_PART('hour', diff_interval);
  IF units IN ('hh', 'hour') THEN
     RETURN diff;
  END IF;
  diff = diff * 60 + DATE_PART('minute', diff_interval);
  IF units IN ('mi', 'n', 'minute') THEN
     RETURN diff;
  END IF;
  diff = diff * 60 + DATE_PART('second', diff_interval);
  RETURN diff;
END;
$$ LANGUAGE plpgsql IMMUTABLE
;


DROP FUNCTION IF EXISTS hivemind_app.calculate_time_part_of_trending(_post_created_at hivemind_app.hive_posts.created_at%TYPE ) CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_time_part_of_trending(
  _post_created_at hivemind_app.hive_posts.created_at%TYPE)
    RETURNS double precision
    LANGUAGE 'plpgsql'
    IMMUTABLE
AS $BODY$
DECLARE
  result double precision;
  sec_from_epoch INT = 0;
BEGIN
  sec_from_epoch  = hivemind_app.date_diff( 'second', CAST('19700101' AS TIMESTAMP), _post_created_at );
  result = sec_from_epoch/240000.0;
  return result;
END;
$BODY$
;


DROP FUNCTION IF EXISTS hivemind_app.calculate_time_part_of_hot(_post_created_at hivemind_app.hive_posts.created_at%TYPE ) CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_time_part_of_hot(
  _post_created_at hivemind_app.hive_posts.created_at%TYPE)
    RETURNS double precision
    LANGUAGE 'plpgsql'
    IMMUTABLE
AS $BODY$
DECLARE
  result double precision;
  sec_from_epoch INT = 0;
BEGIN
  sec_from_epoch  = hivemind_app.date_diff( 'second', CAST('19700101' AS TIMESTAMP), _post_created_at );
  result = sec_from_epoch/10000.0;
  return result;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_rhsares_part_of_hot_and_trend(_rshares hivemind_app.hive_posts.vote_rshares%TYPE) CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_rhsares_part_of_hot_and_trend(_rshares hivemind_app.hive_posts.vote_rshares%TYPE)
RETURNS double precision
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
DECLARE
    mod_score double precision;
BEGIN
    mod_score := _rshares / 10000000.0;
    IF ( mod_score > 0 )
    THEN
        return log( greatest( abs(mod_score), 1 ) );
    END IF;
    return  -1.0 * log( greatest( abs(mod_score), 1 ) );
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_hot(hive_posts.vote_rshares%TYPE, hivemind_app.hive_posts.created_at%TYPE);
CREATE OR REPLACE FUNCTION hivemind_app.calculate_hot(
    _rshares hivemind_app.hive_posts.vote_rshares%TYPE,
    _post_created_at hivemind_app.hive_posts.created_at%TYPE)
RETURNS hivemind_app.hive_posts.sc_hot%TYPE
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
BEGIN
    return hivemind_app.calculate_rhsares_part_of_hot_and_trend(_rshares) + hivemind_app.calculate_time_part_of_hot( _post_created_at );
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_trending(hive_posts.vote_rshares%TYPE, hivemind_app.hive_posts.created_at%TYPE);
CREATE OR REPLACE FUNCTION hivemind_app.calculate_trending(
    _rshares hivemind_app.hive_posts.vote_rshares%TYPE,
    _post_created_at hivemind_app.hive_posts.created_at%TYPE)
RETURNS hivemind_app.hive_posts.sc_trend%TYPE
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
BEGIN
    return hivemind_app.calculate_rhsares_part_of_hot_and_trend(_rshares) + hivemind_app.calculate_time_part_of_trending( _post_created_at );
END;
$BODY$
;

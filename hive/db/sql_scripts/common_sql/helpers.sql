DROP FUNCTION IF EXISTS hivemind_helpers.valid_community;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_community(
  _name TEXT, 
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _name IS NULL OR _name = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION 'community name cannot be blank';
    END IF;

    RETURN _name;
  END IF;

  IF NOT hivemind_helpers.check_community(_name) THEN  
	RAISE EXCEPTION 'given community name is not valid';
  END IF;

  RETURN _name;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_account;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_account(  
  _name TEXT, 
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  name_segment TEXT := '[a-z][a-z0-9\-]+[a-z0-9]';
BEGIN
  IF _name IS NULL OR _name = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION 'invalid account (not specified)';
    END IF;

    RETURN _name;
  END IF;

  IF LENGTH(_name) < 3 OR LENGTH(_name) > 16 THEN
      RAISE EXCEPTION 'invalid account name length: ''%''', _name;
  END IF;

  IF SUBSTRING(_name FROM 1 FOR 1) = '@' THEN
    RAISE EXCEPTION 'invalid account name char ''@''';
  END IF;

  IF _name ~ ('^'|| name_segment ||'(?:\.'|| name_segment ||')*$') THEN
    RETURN _name;
  ELSE
    RAISE EXCEPTION 'invalid account char';
  END IF;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_permlink;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_permlink(  
  _permlink TEXT, 
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _permlink IS NULL OR _permlink = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION 'permlink cannot be blank';
    END IF;

    RETURN _permlink;
  END IF;

  IF LENGTH(_permlink) <= 256 THEN
    RETURN _permlink;
  ELSE
    RAISE EXCEPTION 'invalid permlink length';
  END IF;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_sort;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_sort(  
  _sort TEXT, 
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
    valid_sorts TEXT[] := ARRAY['trending', 'promoted', 'hot', 'created', 'payout', 'payout_comments', 'muted'];
BEGIN
  IF _sort IS NULL OR _sort = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION 'sort must be specified';
    END IF;

    RETURN _sort;
  END IF;

  IF NOT _sort = ANY(valid_sorts) THEN
    RAISE EXCEPTION 'Invalid sort ''%''', _sort;
  END IF;

  RETURN _sort;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_tag;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_tag(  
  _tag TEXT, 
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _tag IS NULL OR _tag = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION 'tag was blank';
    END IF;
    RETURN _tag;
  END IF;

  IF NOT _tag ~ '^[a-z0-9-_]+$' THEN
      RAISE EXCEPTION 'Invalid tag ''%''', _tag;
  END IF;

  RETURN _tag;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_number;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_number(  
  _num NUMERIC, 
  default_num INT, 
  _name TEXT DEFAULT 'integer value', 
  lbound INT DEFAULT NULL, 
  ubound INT DEFAULT NULL
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  validated_num INT;
BEGIN
  IF _num IS NULL THEN
    IF default_num IS NULL THEN
        RAISE EXCEPTION '% must be provided', _name;
    ELSE
        RETURN default_num;
    END IF;
  END IF;

  validated_num := _num::INT;

/*
  -- i dont know if its necessary after rewriting
  BEGIN
      validated_num := _num::INT;
  EXCEPTION
      WHEN OTHERS THEN
          RAISE EXCEPTION '%', SQLERRM;
  END;
*/

  IF lbound IS NOT NULL AND ubound IS NOT NULL THEN
    IF NOT (lbound <= validated_num AND validated_num <= ubound) THEN
        RAISE EXCEPTION '% = % outside valid range [%:%]', _name, validated_num, lbound, ubound;
    END IF;
  END IF;

  RETURN validated_num;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.json_date;
CREATE OR REPLACE FUNCTION hivemind_helpers.json_date(_date TIMESTAMPTZ DEFAULT NULL)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _date IS NULL OR _date = '9999-12-31 23:59:59+00'::TIMESTAMPTZ THEN
      RETURN '1969-12-31T23:59:59';
  END IF;

  RETURN TO_CHAR(_date, 'YYYY-MM-DD') || 'T' || TO_CHAR(_date, 'HH24:MI:SS');

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.get_hive_accounts_info_view_query_string;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_hive_accounts_info_view_query_string(
  _names TEXT[], 
  lite BOOLEAN DEFAULT FALSE
)
  RETURNS SETOF hivemind_app.hive_accounts_info_view
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN

IF lite THEN
  RETURN QUERY (
  SELECT 
    ha.id,
    ha.name,
    ha.post_count,
    ha.created_at,
    NULL::timestamp without time zone as active_at,   
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
  FROM hivemind_app.hive_accounts_info_view_lite ha
  WHERE ha.name = ANY(_names)
  );

ELSE
  RETURN QUERY (
  SELECT 
    ha.id,
    ha.name,
    ha.post_count,
    ha.created_at,
    ha.active_at,  
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
  FROM hivemind_app.hive_accounts_info_view ha
  WHERE ha.name = ANY(_names)
  );

END IF;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_limit;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_limit(  
  _limit NUMERIC, 
  ubound INT,
  default_num INT
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_helpers.valid_number(_limit, default_num, 'limit', 1, ubound);
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_score;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_score(  
  _score NUMERIC, 
  ubound INT,
  default_num INT
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_helpers.valid_number(_score, default_num, 'score', 0, ubound);
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_truncate;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_truncate(  
  _truncate_body NUMERIC, 
  ubound INT,
  default_num INT
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_helpers.valid_number(_truncate_body, 0, 'truncate_body');
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_offset;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_offset(  
  _offset NUMERIC, 
  ubound INT
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  __offset INT := _offset::INT;
BEGIN
  IF __offset >= -1 THEN
    IF ubound IS NOT NULL AND NOT (__offset <= ubound) THEN
      RAISE EXCEPTION 'offset too large';
    END IF;

    RETURN __offset;
  ELSE
    RAISE EXCEPTION 'offset cannot be negative';
  END IF;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_follow_type;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_follow_type(_follow_type TEXT)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  CASE
      WHEN _follow_type = 'blog' THEN
          RETURN 1;
      WHEN _follow_type = 'ignore' THEN
          RETURN 2;
      ELSE
          RAISE EXCEPTION 'Unsupported follow type, valid types: blog, ignore';
  END CASE;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.valid_date;
CREATE OR REPLACE FUNCTION hivemind_helpers.valid_date(
  _date TEXT, 
  _allow_empty BOOLEAN DEFAULT FALSE
) 
  RETURNS void
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _date IS NULL OR _date = '' THEN
    IF NOT _allow_empty THEN
      RAISE EXCEPTION 'Date is blank';
    END IF;
  ELSE
    BEGIN
      PERFORM to_timestamp(_date, 'YYYY-MM-DD HH24:MI:SS');
      RETURN;
      EXCEPTION WHEN others THEN
      NULL; -- Suppress the exception, continue to the next format check
    END;

    BEGIN
      PERFORM to_timestamp(_date, 'YYYY-MM-DD"T"HH24:MI:SS');
      RETURN;
        EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Date should be in format Y-m-d H:M:S or Y-m-dTH:M:S';
    END;
  END IF;
END;
$BODY$
;

--If i see correctly to_nai and parse_amount are used only in case when 'value' is '1.001 HIVE' etc - so i skip the nai parsing.
DROP FUNCTION IF EXISTS hivemind_helpers.to_nai;
CREATE OR REPLACE FUNCTION hivemind_helpers.to_nai(_dec_amount NUMERIC, unit hivemind_helpers.unit_type) 
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$BODY$
BEGIN

RETURN (
WITH calculate_nai_type AS 
(
  SELECT ROUND(_dec_amount * (10^(nm.precision))) as amount, nm.nai, nm.precision
  FROM hivemind_helpers.nai_map nm
  WHERE nm.name = unit

)
  SELECT jsonb_build_object(
    'amount', cnt.amount,
    'nai', cnt.nai,
    'precision', cnt.precision)
  FROM calculate_nai_type cnt);

END;
$BODY$
;

DROP TYPE IF EXISTS hivemind_helpers.parse_amount_type CASCADE;
CREATE TYPE hivemind_helpers.parse_amount_type AS (
  dec_amount NUMERIC, 
  unit hivemind_helpers.unit_type

);

--SELECT * FROM hivemind_helpers.parse_amount('1.001 HBD')
DROP FUNCTION IF EXISTS hivemind_helpers.parse_amount;
CREATE OR REPLACE FUNCTION hivemind_helpers.parse_amount(
  _value VARCHAR(30)
) 
RETURNS hivemind_helpers.parse_amount_type
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
  unit VARCHAR(5) := split_part(_value, ' ', 2);
  dec_amount NUMERIC;
BEGIN
  IF unit = 'SBD' THEN
      unit := 'HBD';
  ELSIF unit = 'STEEM' THEN
      unit := 'HIVE';
  END IF;
  unit := unit::hivemind_helpers.unit_type;
  dec_amount := split_part(_value, ' ', 1)::NUMERIC;

  RETURN (dec_amount, unit)::hivemind_helpers.parse_amount_type;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.database_post_object;
CREATE OR REPLACE FUNCTION hivemind_helpers.database_post_object(
  _row hivemind_app.database_api_post, 
  _truncate_body INT DEFAULT 0
)     
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
  post JSONB;
  curator_payout hivemind_helpers.parse_amount_type := hivemind_helpers.parse_amount(_row.curator_payout_value);
  max_accepted hivemind_helpers.parse_amount_type := hivemind_helpers.parse_amount(_row.max_accepted_payout);
BEGIN

  post := jsonb_build_object(
      'author_rewards', _row.author_rewards,
      'id', _row.id,
      'author', _row.author,
      'permlink', _row.permlink,
      'category', COALESCE(_row.category, 'undefined'),
      'title', _row.title,
      'body', CASE WHEN _truncate_body > 0 THEN LEFT(_row.body, _truncate_body) ELSE _row.body END,
      'json_metadata', _row.json,
      'created', hivemind_helpers.json_date(_row.created_at),
      'last_update', hivemind_helpers.json_date(_row.updated_at),
      'depth', (_row.depth)::INT,
      'children', (_row.children)::INT,
      'last_payout', hivemind_helpers.json_date(_row.last_payout_at),
      'cashout_time', hivemind_helpers.json_date(_row.cashout_time),
      'max_cashout_time', hivemind_helpers.json_date(NULL),
      'curator_payout_value', hivemind_helpers.to_nai(curator_payout.dec_amount, curator_payout.unit),
      'total_payout_value', hivemind_helpers.to_nai((_row.payout - curator_payout.dec_amount), 'HBD'),
      'reward_weight', 10000,
      'root_author', _row.root_author,
      'root_permlink', _row.root_permlink,
      'allow_replies', (_row.allow_replies)::BOOLEAN,
      'allow_votes', (_row.allow_votes)::BOOLEAN,
      'allow_curation_rewards', (_row.allow_curation_rewards)::BOOLEAN,
      'parent_author', _row.parent_author,
      'parent_permlink', _row.parent_permlink_or_category,
      'beneficiaries', _row.beneficiaries, 
      'max_accepted_payout', hivemind_helpers.to_nai(max_accepted.dec_amount, max_accepted.unit),
      'percent_hbd', (_row.percent_hbd)::INT,
      'net_votes', (_row.net_votes)::INT
  );

  IF _row.is_paidout::BOOLEAN THEN
      post := post || jsonb_build_object(
          'total_vote_weight', 0,
          'vote_rshares', 0,
          'net_rshares', 0,
          'abs_rshares', 0,
          'children_abs_rshares', 0
      );
  ELSE
      post := post || jsonb_build_object(
          'total_vote_weight', (_row.total_vote_weight)::BIGINT,
          'vote_rshares', ((_row.rshares)::BIGINT + (_row.abs_rshares)::BIGINT) / 2,
          'net_rshares', (_row.rshares)::BIGINT,
          'abs_rshares', (_row.abs_rshares)::BIGINT,
          'children_abs_rshares', 0
      );
  END IF;

  RETURN post;
    
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.notify_type;
CREATE OR REPLACE FUNCTION hivemind_helpers.notify_type(IN _type SMALLINT)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
BEGIN
  CASE
      WHEN _type = 1 THEN
          RETURN 'new_community';
      WHEN _type = 2 THEN
          RETURN 'set_role';
      WHEN _type = 3 THEN
          RETURN 'set_props';
      WHEN _type = 4 THEN
          RETURN 'set_label';
      WHEN _type = 5 THEN
          RETURN 'mute_post';
      WHEN _type = 6 THEN
          RETURN 'unmute_post';
      WHEN _type = 7 THEN
          RETURN 'pin_post';
      WHEN _type = 8 THEN
          RETURN 'unpin_post';
      WHEN _type = 9 THEN
          RETURN 'flag_post';
      WHEN _type = 10 THEN
          RETURN 'error';
      WHEN _type = 11 THEN
          RETURN 'subscribe';
      WHEN _type = 12 THEN
          RETURN 'reply';
      WHEN _type = 13 THEN
          RETURN 'reply_comment';
      WHEN _type = 14 THEN
          RETURN 'reblog';
      WHEN _type = 15 THEN
          RETURN 'follow';
      WHEN _type = 16 THEN
          RETURN 'mention';
      WHEN _type = 17 THEN
          RETURN 'vote';
      ELSE
  END CASE;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.render_msg;
CREATE OR REPLACE FUNCTION hivemind_helpers.render_msg(IN _row hivemind_app.notification)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
BEGIN
  CASE
      WHEN _row.type_id = 1 THEN
          RETURN format('%s was created',
           '@' || _row.dst);
      WHEN _row.type_id = 2 THEN
          RETURN format('%s set %s %s',
           '@' || _row.src, 
           '@' || _row.dst, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 3 THEN
          RETURN format('%s set properties %s',
           '@' || _row.src, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 4 THEN
          RETURN format('%s label %s %s',
           '@' || _row.src, 
           '@' || _row.dst, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 5 THEN
          RETURN format('%s mute %s - %s',
           '@' || _row.src, 
           '@' || _row.author || '/' || _row.permlink, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 6 THEN
          RETURN format('%s unmute %s - %s',
           '@' || _row.src, 
           '@' || _row.author || '/' || _row.permlink, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 7 THEN
          RETURN format('%s pin %s',
           '@' || _row.src, 
           '@' || _row.author || '/' || _row.permlink);
      WHEN _row.type_id = 8 THEN
          RETURN format('%s unpin %s',
           '@' || _row.src, 
           '@' || _row.author || '/' || _row.permlink);
      WHEN _row.type_id = 9 THEN
          RETURN format('%s flag %s - %s',
           '@' || _row.src, 
           '@' || _row.author || '/' || _row.permlink, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 10 THEN
          RETURN format('error: %s',
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      WHEN _row.type_id = 11 THEN
          RETURN format('%s subscribed to %s',
           '@' || _row.src, 
           _row.community_title);
      WHEN _row.type_id = 12 THEN
          RETURN format('%s replied to your post',
           '@' || _row.src);
      WHEN _row.type_id = 13 THEN
          RETURN format('%s replied to your comment',
           '@' || _row.src);
      WHEN _row.type_id = 14 THEN
          RETURN format('%s reblogged your post',
           '@' || _row.src);
      WHEN _row.type_id = 15 THEN
          RETURN format('%s followed you',
           '@' || _row.src);
      WHEN _row.type_id = 16 THEN
          RETURN format('%s mentioned you and %s others',
           '@' || _row.src, 
           _row.number_of_mentions - 1);
      WHEN _row.type_id = 17 THEN
          RETURN format('%s voted on your post %s',
           '@' || _row.src, 
           (CASE WHEN _row.payload IS NULL THEN 'null' ELSE _row.payload END));
      ELSE
  END CASE;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.render_url;
CREATE OR REPLACE FUNCTION hivemind_helpers.render_url(IN _row hivemind_app.notification)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
BEGIN
  IF _row.permlink IS NOT NULL AND _row.permlink::TEXT != '' THEN
    RETURN '@' || _row.author || '/' || _row.permlink;
  END IF;
  
  IF _row.community IS NOT NULL AND _row.community::TEXT != '' THEN
    RETURN 'trending/' || _row.community;
  END IF;
  
  IF _row.src IS NOT NULL AND _row.src::TEXT != '' THEN
    RETURN '@' || _row.src;
  END IF;

  IF _row.dst IS NOT NULL AND _row.dst::TEXT != '' THEN
    RETURN '@' || _row.dst;
  END IF;

  RETURN NULL::TEXT;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.parse_argument;
CREATE FUNCTION hivemind_helpers.parse_argument(_params JSON, _json_type TEXT, _arg_name TEXT, _arg_number INT, _is_bool BOOLEAN = FALSE)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __param TEXT;
BEGIN
  SELECT CASE WHEN _json_type = 'object' THEN
    _params->>_arg_name
  ELSE
    _params->>_arg_number
  END INTO __param;

  -- TODO: this is done to replicate behaviour of HAfAH python, might remove
  IF _is_bool IS TRUE AND __param ~ '([A-Z].+)' THEN
    RAISE invalid_text_representation;
  ELSE
    RETURN __param;
  END IF;
END
$$
;

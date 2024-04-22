DROP TYPE IF EXISTS hivemind_helpers.unread_notifications_type CASCADE;
CREATE TYPE hivemind_helpers.unread_notifications_type AS (
  lastread_at timestamp without time zone, 
  unread INT
);

--SELECT * FROM hivemind_helpers.unread_notifications('gtg')
DROP FUNCTION IF EXISTS hivemind_helpers.unread_notifications;
CREATE OR REPLACE FUNCTION hivemind_helpers.unread_notifications(
  IN account TEXT,
  IN min_score INT DEFAULT 25
)
    RETURNS hivemind_helpers.unread_notifications_type
    LANGUAGE plpgsql
    STABLE
AS
$BODY$
DECLARE
  _author TEXT = hivemind_helpers.valid_account(account);
  _min_score SMALLINT = hivemind_helpers.valid_score(min_score, 100, 25)::SMALLINT;
BEGIN
  RETURN (lastread_at, unread)::hivemind_helpers.unread_notifications_type
  FROM hivemind_app.get_number_of_unread_notifications(_author, _min_score);
END;
$BODY$
;

DROP TYPE IF EXISTS hivemind_helpers.account_notifications_type CASCADE;
CREATE TYPE hivemind_helpers.account_notifications_type AS (
  date TEXT, 
  id BIGINT, 
  msg TEXT, 
  score SMALLINT, 
  type TEXT, 
  url TEXT
);

--SELECT * FROM hivemind_helpers.account_notifications('blocktrades')
DROP FUNCTION IF EXISTS hivemind_helpers.account_notifications;
CREATE OR REPLACE FUNCTION hivemind_helpers.account_notifications(
  IN account TEXT,
  IN min_score INT DEFAULT 25,
  IN last_id BIGINT DEFAULT NULL,
  IN "limit" INT DEFAULT 100
)
    RETURNS SETOF hivemind_helpers.account_notifications_type
    LANGUAGE plpgsql
    STABLE
AS
$BODY$
DECLARE
  _author TEXT = hivemind_helpers.valid_account(account);
  _min_score SMALLINT = hivemind_helpers.valid_score(min_score, 100, 25)::SMALLINT;
  _last_id BIGINT = hivemind_helpers.valid_number(last_id, 0, 'last_id')::BIGINT;
  __limit SMALLINT = hivemind_helpers.valid_limit("limit", 100, 100)::SMALLINT;
BEGIN
  RETURN QUERY (
    SELECT 
      hivemind_helpers.json_date(an.created_at::TIMESTAMPTZ),
      an.id,
      hivemind_helpers.render_msg((an.*)::hivemind_app.notification),
      an.score,
      hivemind_helpers.notify_type(an.type_id),
      hivemind_helpers.render_url((an.*)::hivemind_app.notification)
    FROM hivemind_app.account_notifications(_author, _min_score, _last_id, __limit) an
);

END;
$BODY$
;

--SELECT * FROM hivemind_helpers.post_notifications('blocktrades','2nd-update-of-2024-releasing-the-new-haf-based-stack-for-hive-api-nodes')
DROP FUNCTION IF EXISTS hivemind_helpers.post_notifications;
CREATE OR REPLACE FUNCTION hivemind_helpers.post_notifications(
  IN author TEXT,
  IN permlink TEXT,
  IN min_score INT DEFAULT 25,
  IN last_id BIGINT DEFAULT NULL,
  IN "limit" INT DEFAULT 100
)
    RETURNS SETOF hivemind_helpers.account_notifications_type
    LANGUAGE plpgsql
    STABLE
AS
$BODY$
DECLARE
  _author TEXT = hivemind_helpers.valid_account(author);
  _permlink TEXT = hivemind_helpers.valid_permlink(permlink);
  _min_score SMALLINT = hivemind_helpers.valid_score(min_score, 100, 25)::SMALLINT;
  _last_id BIGINT = hivemind_helpers.valid_number(last_id, 0, 'last_id')::BIGINT;
  __limit SMALLINT = hivemind_helpers.valid_limit("limit", 100, 100)::SMALLINT;
BEGIN
  RETURN QUERY (
    SELECT 
      an.id,
      hivemind_helpers.notify_type(an.type_id),
      an.score,
      hivemind_helpers.json_date(an.created_at::TIMESTAMPTZ),
      hivemind_helpers.render_msg((an.*)::hivemind_app.notification),
      hivemind_helpers.render_url((an.*)::hivemind_app.notification)
    FROM hivemind_app.post_notifications(_author, _permlink, _min_score, _last_id, __limit) an
);

END;
$BODY$
;

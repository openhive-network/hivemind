-- The shared hivemind service's clone API, installed by serve.sh into the
-- hivemind_shared database as postgres on every start (idempotent). Modelled on
-- hive/haf's .aidev/shared-haf/admin.sql.
--
-- The cluster holds one frozen template per hivemind schema revision,
-- hivemind_<revision>: HAF's 5M replay with hivemind installed, mocked and
-- synced by seed.sh. Each test run gets its own database, run_<id>, created
-- from one of them with STRATEGY FILE_COPY: under file_copy_method = clone on
-- ZFS that clones the template's files instead of copying them. CREATE/DROP
-- DATABASE cannot run inside a function's transaction, so they go through a
-- dblink loopback connection as postgres. The run is registered (and committed)
-- before its database exists, so the reaper never mistakes a clone in progress
-- for an orphan.
--
-- A consumer whose revision has no template asks for one with request_seed();
-- the seeder (seeder.sh) works through the requests one at a time.

create schema if not exists dblink;
revoke all on schema dblink from public;
create extension if not exists dblink with schema dblink;

create schema if not exists hivemind_shared;

-- The role consumers log in as, without a password (the compose file trusts the
-- fleet's LAN): it may create and drop run databases and ask for seeds. Inside
-- its clone a run works as `hivemind`, the role that owns hivemind's schemas.
do $$
begin
    create role hivemind_shared_consumer login;
exception when duplicate_object then
    null;
end
$$;

create table if not exists hivemind_shared.templates (
    revision text primary key,
    database_name text not null unique,
    haf_commit text not null,
    hivemind_commit text not null,
    head_block bigint not null,
    seeded_at timestamptz not null default now()
);

create table if not exists hivemind_shared.run_databases (
    run_id text primary key,
    database_name text not null unique,
    revision text not null,
    created_by name not null,
    created_at timestamptz not null default now()
);

-- One request per revision: pending -> seeding -> done | failed.
create table if not exists hivemind_shared.seed_requests (
    revision text primary key,
    hivemind_commit text not null,
    state text not null default 'pending' check (state in ('pending', 'seeding', 'done', 'failed')),
    detail text,
    requested_by name not null,
    requested_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function hivemind_shared._loopback(_database text, _sql text)
returns void
language plpgsql
set search_path = pg_catalog
as $$
begin
    perform dblink.dblink_exec(
        format('dbname=%s user=postgres port=%s', _database, current_setting('port')),
        _sql);
end
$$;

create or replace function hivemind_shared._run_database_name(_run_id text)
returns text
language plpgsql
immutable
as $$
begin
    if _run_id is null or _run_id !~ '^[a-z0-9][a-z0-9_-]{0,47}$' then
        raise exception 'run id must be 1-48 lowercase letters, digits, "_" or "-", starting with a letter or digit, got %', _run_id
            using errcode = 'invalid_parameter_value';
    end if;
    return 'run_' || _run_id;
end
$$;

create or replace function hivemind_shared._check_revision(_revision text)
returns void
language plpgsql
immutable
as $$
begin
    if _revision is null or _revision !~ '^[0-9a-f]{40}$' then
        raise exception 'schema revision must be 40 lowercase hex digits, got %', _revision
            using errcode = 'invalid_parameter_value';
    end if;
end
$$;

-- Creates the run's database as a clone of the template for _revision (the
-- newest template when null), owned by the caller, and returns its name.
-- Raises no_data_found when no template matches, unique_violation when the run
-- already has a database.
create or replace function hivemind_shared.clone_run_database(_run_id text, _revision text default null)
returns text
language plpgsql
security definer
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _name text := hivemind_shared._run_database_name(_run_id);
    _template hivemind_shared.templates;
begin
    if _revision is not null then
        perform hivemind_shared._check_revision(_revision);
    end if;
    select * into _template from hivemind_shared.templates t
    where _revision is null or t.revision = _revision
    order by t.seeded_at desc limit 1;
    if not found then
        raise exception 'no hivemind template for schema revision %', coalesce(_revision, '(any)')
            using errcode = 'no_data_found';
    end if;
    perform hivemind_shared._loopback(current_database(), format(
        'insert into hivemind_shared.run_databases (run_id, database_name, revision, created_by) values (%L, %L, %L, %L)',
        _run_id, _name, _template.revision, session_user));
    begin
        perform hivemind_shared._loopback('postgres', format(
            'create database %I owner %I template %I strategy file_copy',
            _name, session_user, _template.database_name));
        -- A template copies data, not the ACL (see seed.sh).
        perform hivemind_shared._loopback('postgres', format(
            'grant create on database %I to hive_applications_owner_group', _name));
    exception when others then
        perform hivemind_shared._loopback(current_database(), format(
            'delete from hivemind_shared.run_databases where run_id = %L', _run_id));
        raise;
    end;
    return _name;
end
$$;

-- Drops the run's database (closing its connections) and forgets the run.
-- A run without a database is not an error.
create or replace function hivemind_shared.drop_run_database(_run_id text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _name text := hivemind_shared._run_database_name(_run_id);
begin
    perform hivemind_shared._loopback('postgres', format('drop database if exists %I with (force)', _name));
    delete from hivemind_shared.run_databases where run_id = _run_id;
end
$$;

-- Asks the seeder for a template of _revision, synced from _commit (a hivemind
-- commit whose update_db_patchlevel.sql yields _revision). Returns the
-- revision's state afterwards: 'seeded' when a template exists already, else
-- the request's state. A failed request is retried only for another commit.
create or replace function hivemind_shared.request_seed(_revision text, _commit text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _state text;
begin
    perform hivemind_shared._check_revision(_revision);
    if _commit is null or _commit !~ '^[0-9a-f]{40}$' then
        raise exception 'commit must be a full 40-character commit SHA, got %', _commit
            using errcode = 'invalid_parameter_value';
    end if;
    if exists (select 1 from hivemind_shared.templates t where t.revision = _revision) then
        return 'seeded';
    end if;
    insert into hivemind_shared.seed_requests as r (revision, hivemind_commit, requested_by)
    values (_revision, _commit, session_user)
    on conflict (revision) do update
        set hivemind_commit = excluded.hivemind_commit, state = 'pending', detail = null,
            requested_by = excluded.requested_by, requested_at = now(), updated_at = now()
        where r.state in ('failed', 'done') and r.hivemind_commit <> excluded.hivemind_commit
    returning state into _state;
    if _state is null then
        select r.state into _state from hivemind_shared.seed_requests r where r.revision = _revision;
    end if;
    return _state;
end
$$;

-- Drops every run database created more than _ttl ago, and every run_*
-- database no run is registered for (left by a failed clone or a lost
-- registry); forgets runs whose database is gone. Returns the dropped names.
create or replace function hivemind_shared.reap_run_databases(_ttl interval default interval '6 hours')
returns setof text
language plpgsql
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _name text;
begin
    for _name in
        select r.database_name from hivemind_shared.run_databases r
        where r.created_at < now() - _ttl
        union
        select d.datname from pg_database d
        where d.datname like 'run\_%'
          and not exists (select 1 from hivemind_shared.run_databases r where r.database_name = d.datname)
    loop
        perform hivemind_shared._loopback('postgres', format('drop database if exists %I with (force)', _name));
        delete from hivemind_shared.run_databases where database_name = _name;
        return next _name;
    end loop;
    -- A clone commits its registration before creating the database, so give it a minute.
    delete from hivemind_shared.run_databases r
    where r.created_at < now() - interval '1 minute'
      and not exists (select 1 from pg_database d where d.datname = r.database_name);
end
$$;

-- What the service serves: one row per template (its schema revision, the HAF
-- and hivemind commits it was synced from, its head block) with the live run
-- databases cloned from it.
create or replace function hivemind_shared.health()
returns table (revision text, template text, haf_commit text, hivemind_commit text, head_block bigint,
               seeded_at timestamptz, run_databases bigint)
language sql
stable
security definer
set search_path = pg_catalog, hivemind_shared
as $$
    select t.revision, t.database_name, t.haf_commit, t.hivemind_commit, t.head_block, t.seeded_at,
           (select count(*) from hivemind_shared.run_databases r
            join pg_database d on d.datname = r.database_name
            where r.revision = t.revision)
    from hivemind_shared.templates t
    order by t.seeded_at desc
$$;

revoke all on all functions in schema hivemind_shared from public;
revoke all on all tables in schema hivemind_shared from public;
grant usage on schema hivemind_shared to hivemind_shared_consumer;
grant select on hivemind_shared.seed_requests to hivemind_shared_consumer;
grant execute on function hivemind_shared.clone_run_database(text, text), hivemind_shared.drop_run_database(text),
    hivemind_shared.request_seed(text, text), hivemind_shared.health()
    to hivemind_shared_consumer;

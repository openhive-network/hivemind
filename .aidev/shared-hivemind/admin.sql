-- The shared hivemind service's clone API, installed by serve.sh into the
-- hivemind_shared database as postgres on every start (idempotent). Modelled on
-- hive/haf's .aidev/shared-haf/admin.sql.
--
-- The cluster holds frozen templates keyed by (hivemind schema revision, sync
-- recipe), hivemind_<revision>_<recipe prefix>: HAF's 5M replay with hivemind
-- installed, mocked and synced by seed.sh. The recipe (shared_fixture.py) hashes
-- what decides the synced data besides the schema: the mocks, the indexer, the
-- apps' commits, seed.sh and the HAF commit. Each test run gets its own database, run_<id>, created
-- from one of them with STRATEGY FILE_COPY: under file_copy_method = clone on
-- ZFS that clones the template's files instead of copying them. CREATE/DROP
-- DATABASE cannot run inside a function's transaction, so they go through a
-- dblink loopback connection as postgres. The run is registered (and committed)
-- before its database exists, so the reaper never mistakes a clone in progress
-- for an orphan.
--
-- A consumer whose (revision, recipe) has no template asks for one with
-- request_seed(); the seeder (seeder.sh) works through the requests one at a
-- time, and retires a revision's older templates (drop_template()).

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
    revision text not null,
    recipe text not null,
    database_name text not null unique,
    haf_commit text not null,
    hivemind_commit text not null,
    head_block bigint not null,
    seeded_at timestamptz not null default now(),
    primary key (revision, recipe)
);

create table if not exists hivemind_shared.run_databases (
    run_id text primary key,
    database_name text not null unique,
    revision text not null,
    template text,
    created_by name not null,
    created_at timestamptz not null default now()
);

-- Templates and runs from before the recipe joined the key: such a template is
-- recorded with recipe 'unrecorded', which no tree's recipe matches, and such a
-- run with no template (it counts against every template of its revision).
-- The seed requests are a queue the ref polling and the next miss refill.
do $$
begin
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'hivemind_shared' and table_name = 'templates' and column_name = 'recipe') then
        alter table hivemind_shared.templates add column recipe text not null default 'unrecorded';
        alter table hivemind_shared.templates alter column recipe drop default;
        alter table hivemind_shared.templates drop constraint templates_pkey;
        alter table hivemind_shared.templates add primary key (revision, recipe);
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'hivemind_shared' and table_name = 'run_databases' and column_name = 'template') then
        alter table hivemind_shared.run_databases add column template text;
    end if;
    if to_regclass('hivemind_shared.seed_requests') is not null
       and not exists (select 1 from information_schema.columns
                       where table_schema = 'hivemind_shared' and table_name = 'seed_requests' and column_name = 'recipe') then
        drop table hivemind_shared.seed_requests;
    end if;
end
$$;
drop function if exists hivemind_shared.clone_run_database(text, text);
drop function if exists hivemind_shared.request_seed(text, text);
do $$
begin
    if exists (select 1 from pg_proc p where p.oid = to_regprocedure('hivemind_shared.health()')
               and pg_get_function_result(p.oid) not like '%recipe%') then
        drop function hivemind_shared.health();
    end if;
end
$$;

-- One request per (revision, recipe): pending -> seeding -> done | failed.
create table if not exists hivemind_shared.seed_requests (
    revision text not null,
    recipe text not null,
    hivemind_commit text not null,
    state text not null default 'pending' check (state in ('pending', 'seeding', 'done', 'failed')),
    detail text,
    requested_by name not null,
    requested_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (revision, recipe)
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

create or replace function hivemind_shared._check_recipe(_recipe text)
returns void
language plpgsql
immutable
as $$
begin
    if _recipe is null or _recipe !~ '^[0-9a-f]{64}$' then
        raise exception 'sync recipe must be 64 lowercase hex digits, got %', _recipe
            using errcode = 'invalid_parameter_value';
    end if;
end
$$;

-- Creates the run's database as a clone of the newest template for _revision
-- and _recipe (any, when null), owned by the caller, and returns its name.
-- Raises no_data_found when no template matches, unique_violation when the run
-- already has a database. The template's row stays locked until the clone
-- exists, so drop_template() never drops it from under the clone.
create or replace function hivemind_shared.clone_run_database(_run_id text, _revision text default null,
                                                              _recipe text default null)
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
    where (_revision is null or t.revision = _revision) and (_recipe is null or t.recipe = _recipe)
    order by t.seeded_at desc limit 1
    for share;
    if not found then
        raise exception 'no hivemind template for schema revision % and sync recipe %',
            coalesce(_revision, '(any)'), coalesce(_recipe, '(any)')
            using errcode = 'no_data_found';
    end if;
    perform hivemind_shared._loopback(current_database(), format(
        'insert into hivemind_shared.run_databases (run_id, database_name, revision, template, created_by) values (%L, %L, %L, %L, %L)',
        _run_id, _name, _template.revision, _template.database_name, session_user));
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

-- Runs _script, one of hivemind's admin-level scripts (schema.py's
-- _setup_admin_runtime_code: plpython3u functions, which only a superuser may
-- create), in the run's database as haf_admin, the role `hive setup` installs
-- them as. A run works as `hivemind` and cannot. Raises no_data_found, changing
-- nothing, unless _run_id is a run registered by clone_run_database() whose
-- database exists: never a template, the seed database or any other.
--
-- The script is the caller's, so a consumer runs superuser SQL in its own run
-- database; the service trusts its consumers on the fleet's LAN as it trusts
-- them with request_seed().
create or replace function hivemind_shared.install_admin_script(_run_id text, _script text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _name text := hivemind_shared._run_database_name(_run_id);
begin
    if not exists (select 1 from hivemind_shared.run_databases r
                   join pg_database d on d.datname = r.database_name
                   where r.run_id = _run_id and r.database_name = _name and not d.datistemplate) then
        raise exception 'no run database is registered for run %', _run_id
            using errcode = 'no_data_found';
    end if;
    perform hivemind_shared._loopback(_name, 'set role haf_admin; ' || _script);
end
$$;

-- Asks the seeder for a template of _revision and _recipe, synced from _commit
-- (a hivemind commit whose update_db_patchlevel.sql yields _revision and whose
-- recipe on the provider's HAF is _recipe). Returns the state afterwards:
-- 'seeded' when such a template exists already, else the request's state. A
-- failed request is retried only for another commit; a done one whose template
-- has since been retired is queued again.
create or replace function hivemind_shared.request_seed(_revision text, _recipe text, _commit text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _state text;
begin
    perform hivemind_shared._check_revision(_revision);
    perform hivemind_shared._check_recipe(_recipe);
    if _commit is null or _commit !~ '^[0-9a-f]{40}$' then
        raise exception 'commit must be a full 40-character commit SHA, got %', _commit
            using errcode = 'invalid_parameter_value';
    end if;
    if exists (select 1 from hivemind_shared.templates t where t.revision = _revision and t.recipe = _recipe) then
        return 'seeded';
    end if;
    insert into hivemind_shared.seed_requests as r (revision, recipe, hivemind_commit, requested_by)
    values (_revision, _recipe, _commit, session_user)
    on conflict (revision, recipe) do update
        set hivemind_commit = excluded.hivemind_commit, state = 'pending', detail = null,
            requested_by = excluded.requested_by, requested_at = now(), updated_at = now()
        where r.state = 'done' or (r.state = 'failed' and r.hivemind_commit <> excluded.hivemind_commit)
    returning state into _state;
    if _state is null then
        select r.state into _state from hivemind_shared.seed_requests r
        where r.revision = _revision and r.recipe = _recipe;
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

-- Forgets the template _database and drops it, unless a registered run was
-- cloned from it. Returns 'dropped', 'in use' or 'gone' (no such template).
-- Deleting the row first waits for a clone_run_database() holding it.
create or replace function hivemind_shared.drop_template(_database text)
returns text
language plpgsql
set search_path = pg_catalog, hivemind_shared
as $$
declare
    _template hivemind_shared.templates;
begin
    begin
        delete from hivemind_shared.templates t where t.database_name = _database returning * into _template;
        if not found then
            return 'gone';
        end if;
        if exists (select 1 from hivemind_shared.run_databases r
                   where r.template = _database or (r.template is null and r.revision = _template.revision)) then
            -- Rolls the delete back.
            raise exception 'template % has runs', _database using errcode = 'object_in_use';
        end if;
    exception when object_in_use then
        return 'in use';
    end;
    if exists (select 1 from pg_database d where d.datname = _database) then
        perform hivemind_shared._loopback('postgres', format('alter database %I is_template false', _database));
        perform hivemind_shared._loopback('postgres', format('drop database %I with (force)', _database));
    end if;
    return 'dropped';
end
$$;

-- What the service serves: one row per template, newest first (its schema
-- revision and sync recipe, the HAF and hivemind commits it was synced from,
-- its head block) with the live run databases cloned from it.
create or replace function hivemind_shared.health()
returns table (revision text, recipe text, template text, haf_commit text, hivemind_commit text,
               head_block bigint, seeded_at timestamptz, run_databases bigint)
language sql
stable
security definer
set search_path = pg_catalog, hivemind_shared
as $$
    select t.revision, t.recipe, t.database_name, t.haf_commit, t.hivemind_commit, t.head_block, t.seeded_at,
           (select count(*) from hivemind_shared.run_databases r
            join pg_database d on d.datname = r.database_name
            where r.template = t.database_name or (r.template is null and r.revision = t.revision))
    from hivemind_shared.templates t
    order by t.seeded_at desc
$$;

revoke all on all functions in schema hivemind_shared from public;
revoke all on all tables in schema hivemind_shared from public;
grant usage on schema hivemind_shared to hivemind_shared_consumer;
grant select on hivemind_shared.seed_requests to hivemind_shared_consumer;
grant execute on function hivemind_shared.clone_run_database(text, text, text), hivemind_shared.drop_run_database(text),
    hivemind_shared.install_admin_script(text, text), hivemind_shared.request_seed(text, text, text),
    hivemind_shared.health()
    to hivemind_shared_consumer;

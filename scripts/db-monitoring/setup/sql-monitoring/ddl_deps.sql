/**
Easy way to drop and recreate table or view dependencies, when you need to alter
something in them.
See http://pretius.com/postgresql-stop-worrying-about-table-and-view-dependencies/.
Enhanced by Wojciech Barcik wbarcik@syncad.com (handling of rules).
*/


-- SEQUENCE: deps_saved_ddl_deps_id_seq

-- DROP SEQUENCE deps_saved_ddl_deps_id_seq;

CREATE SEQUENCE deps_saved_ddl_deps_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1;


-- Table: deps_saved_ddl

-- DROP TABLE deps_saved_ddl;

CREATE TABLE deps_saved_ddl
(
    deps_id integer NOT NULL DEFAULT nextval('deps_saved_ddl_deps_id_seq'::regclass),
    deps_view_schema character varying(255) COLLATE pg_catalog."default",
    deps_view_name character varying(255) COLLATE pg_catalog."default",
    deps_ddl_to_run text COLLATE pg_catalog."default",
    CONSTRAINT deps_saved_ddl_pkey PRIMARY KEY (deps_id)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;


-- create table deps_saved_ddl
-- (
--     deps_id serial primary key,
--     deps_view_schema varchar(255),
--     deps_view_name varchar(255),
--     deps_ddl_to_run text
-- );


-- FUNCTION: deps_save_and_drop_dependencies(character varying, character varying, boolean)

-- DROP FUNCTION deps_save_and_drop_dependencies(character varying, character varying, boolean);

CREATE OR REPLACE FUNCTION deps_save_and_drop_dependencies(
    p_view_schema character varying,
    p_view_name character varying,
    drop_relation boolean DEFAULT true
  )
  RETURNS void
  LANGUAGE 'plpgsql'
  COST 100
  VOLATILE
AS $BODY$
/**
From http://pretius.com/postgresql-stop-worrying-about-table-and-view-dependencies/
@wojtek added DDL for rules.

Drops dependencies of view, but saves them into table `deps_saved_ddl`, for
future restoration. Use function `deps_restore_dependencies` to restore
dependencies dropped by this function.
*/
declare
  v_curr record;
begin
for v_curr in
(
  select obj_schema, obj_name, obj_type from
  (
  with recursive recursive_deps(obj_schema, obj_name, obj_type, depth) as
  (
    select p_view_schema, p_view_name, null::varchar, 0
    union
    select dep_schema::varchar, dep_name::varchar, dep_type::varchar,
        recursive_deps.depth + 1 from
    (
      select ref_nsp.nspname ref_schema, ref_cl.relname ref_name,
          rwr_cl.relkind dep_type, rwr_nsp.nspname dep_schema,
          rwr_cl.relname dep_name
      from pg_depend dep
      join pg_class ref_cl on dep.refobjid = ref_cl.oid
      join pg_namespace ref_nsp on ref_cl.relnamespace = ref_nsp.oid
      join pg_rewrite rwr on dep.objid = rwr.oid
      join pg_class rwr_cl on rwr.ev_class = rwr_cl.oid
      join pg_namespace rwr_nsp on rwr_cl.relnamespace = rwr_nsp.oid
      where dep.deptype = 'n'
      and dep.classid = 'pg_rewrite'::regclass
    ) deps
    join recursive_deps on deps.ref_schema = recursive_deps.obj_schema
        and deps.ref_name = recursive_deps.obj_name
    where (deps.ref_schema != deps.dep_schema or deps.ref_name != deps.dep_name)
  )
  select obj_schema, obj_name, obj_type, depth
  from recursive_deps
  where depth > 0
  ) t
  group by obj_schema, obj_name, obj_type
  order by max(depth) desc
) loop

  insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
  select p_view_schema, p_view_name, 'COMMENT ON ' ||
  case
    when c.relkind = 'v' then 'VIEW'
    when c.relkind = 'm' then 'MATERIALIZED VIEW'
  else ''
  end
  || ' ' || n.nspname || '.' || c.relname || ' IS '''
      || replace(d.description, '''', '''''') || ''';'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_description d on d.objoid = c.oid and d.objsubid = 0
  where n.nspname = v_curr.obj_schema and c.relname = v_curr.obj_name
      and d.description is not null;

  insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
  select p_view_schema, p_view_name, 'COMMENT ON COLUMN ' || n.nspname || '.'
      || c.relname || '.' || a.attname || ' IS '''
      || replace(d.description, '''', '''''') || ''';'
  from pg_class c
  join pg_attribute a on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_description d on d.objoid = c.oid and d.objsubid = a.attnum
  where n.nspname = v_curr.obj_schema and c.relname = v_curr.obj_name
      and d.description is not null;

  insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
  select p_view_schema, p_view_name, 'GRANT ' || privilege_type || ' ON '
      || table_schema || '.' || table_name || ' TO ' || grantee
  from information_schema.role_table_grants
  where table_schema = v_curr.obj_schema and table_name = v_curr.obj_name;

  if v_curr.obj_type = 'v' then

    insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
    select p_view_schema, p_view_name, definition
    from pg_catalog.pg_rules
    where schemaname = v_curr.obj_schema and tablename = v_curr.obj_name;

    insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
    select p_view_schema, p_view_name, 'CREATE VIEW '
        || v_curr.obj_schema || '.' || v_curr.obj_name || ' AS ' || view_definition
    from information_schema.views
    where table_schema = v_curr.obj_schema and table_name = v_curr.obj_name;

  elsif v_curr.obj_type = 'm' then
    insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
    select p_view_schema, p_view_name, 'CREATE MATERIALIZED VIEW '
        || v_curr.obj_schema || '.' || v_curr.obj_name || ' AS ' || definition
    from pg_matviews
    where schemaname = v_curr.obj_schema and matviewname = v_curr.obj_name;
  end if;

  if drop_relation = true then
    execute 'DROP ' ||
    case
      when v_curr.obj_type = 'v' then 'VIEW'
      when v_curr.obj_type = 'm' then 'MATERIALIZED VIEW'
    end
    || ' ' || v_curr.obj_schema || '.' || v_curr.obj_name;
  end if;

end loop;
end;
$BODY$;


-- FUNCTION: deps_restore_dependencies(character varying, character varying)

-- DROP FUNCTION deps_restore_dependencies(character varying, character varying);

CREATE OR REPLACE FUNCTION deps_restore_dependencies(
    p_view_schema character varying,
    p_view_name character varying
  )
  RETURNS void
  LANGUAGE 'plpgsql'
  COST 100
  VOLATILE
AS $BODY$
/**
From http://pretius.com/postgresql-stop-worrying-about-table-and-view-dependencies/

Restores dependencies dropped by function `deps_save_and_drop_dependencies`.
*/
declare
  v_curr record;
begin
for v_curr in
(
  select deps_ddl_to_run
  from deps_saved_ddl
  where deps_view_schema = p_view_schema and deps_view_name = p_view_name
  order by deps_id desc
) loop
  execute v_curr.deps_ddl_to_run;
end loop;
delete from deps_saved_ddl
where deps_view_schema = p_view_schema and deps_view_name = p_view_name;
end;
$BODY$;

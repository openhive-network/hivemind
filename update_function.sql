CREATE OR REPLACE FUNCTION hive.unregister_table( _table_schema TEXT,  _table_name TEXT )
    RETURNS void
    LANGUAGE 'plpgsql'
    VOLATILE
AS
$BODY$
DECLARE
    __shadow_table_name TEXT := hive.get_shadow_table_name( _table_schema, _table_name );
    __hive_insert_trigger_name TEXT := hive.get_trigger_insert_name( _table_schema,  _table_name );
    __hive_delete_trigger_name TEXT := hive.get_trigger_delete_name( _table_schema,  _table_name );
    __hive_update_trigger_name TEXT := hive.get_trigger_update_name( _table_schema,  _table_name );
    __hive_truncate_trigger_name TEXT := hive.get_trigger_truncate_name( _table_schema,  _table_name );
    __hive_triggerfunction_name_insert TEXT := hive.get_trigger_insert_function_name( _table_schema,  _table_name );
    __hive_triggerfunction_name_delete TEXT := hive.get_trigger_delete_function_name( _table_schema,  _table_name );
    __hive_triggerfunction_name_update TEXT := hive.get_trigger_update_function_name( _table_schema,  _table_name );
    __hive_triggerfunction_name_truncate TEXT := hive.get_trigger_truncate_function_name( _table_schema,  _table_name );
    __new_sequence_name TEXT := 'seq_' || lower(_table_schema) || '_' || lower(_table_name);
    __context_name TEXT := NULL;
    __registered_table_id INTEGER := NULL;
BEGIN
    SELECT hc.name, hrt.id INTO __context_name, __registered_table_id
    FROM hive.contexts hc
    JOIN hive.registered_tables hrt ON hrt.context_id = hc.id
    WHERE hrt.origin_table_schema = lower(_table_schema) AND hrt.origin_table_name = lower(_table_name)
    ;

    IF __registered_table_id IS NULL THEN
        RAISE EXCEPTION 'Table %s.%s is not registered', lower(_table_schema), lower(_table_name);
    END IF;

    -- drop shadow table
    EXECUTE format( 'DROP TABLE hive.%s CASCADE', __shadow_table_name );

    -- remove information about triggers
    DELETE FROM hive.triggers WHERE registered_table_id = __registered_table_id;

    -- remove entry about the regitered table
    DELETE FROM hive.registered_tables as hrt  WHERE hrt.origin_table_schema = lower( _table_schema ) AND hrt.origin_table_name = lower( _table_name );

    -- drop functions and triggers
    EXECUTE format( 'DROP FUNCTION %s CASCADE', __hive_triggerfunction_name_insert );
    EXECUTE format( 'DROP FUNCTION %s CASCADE', __hive_triggerfunction_name_delete );
    EXECUTE format( 'DROP FUNCTION %s CASCADE', __hive_triggerfunction_name_update );
    EXECUTE format( 'DROP FUNCTION %s CASCADE', __hive_triggerfunction_name_truncate );

    -- drop revert functions
    PERFORM hive.drop_revert_functions( _table_schema, _table_name );

    -- remove inheritance and sequence
    EXECUTE format( 'ALTER TABLE %I.%s NO INHERIT hive.%s', lower(_table_schema), lower(_table_name), __context_name );
    EXECUTE format( 'ALTER TABLE %I.%s DROP COLUMN hive_rowid CASCADE', lower(_table_schema), lower(_table_name)  );
END
$BODY$
;

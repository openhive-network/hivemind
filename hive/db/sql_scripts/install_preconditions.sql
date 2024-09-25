DO
$$
    BEGIN
        ASSERT EXISTS( SELECT 1 FROM information_schema.schemata WHERE schema_name = 'reptracker_app' )
            , 'Reputation tracker with schema reptracker_app is not installed'
        ;
    END
$$;
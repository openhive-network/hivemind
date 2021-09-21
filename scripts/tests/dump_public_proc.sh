#!/bin/bash
USER="hive"
DATABASE="hive"
time pg_dump -Fc -U $USER -d $DATABASE -n public  -v -f hivemind_public.dump;
psql -U $USER -d $DATABASE -c 'alter schema public rename to public_references';
psql -U $USER -d $DATABASE -c 'create schema public';
time pg_restore -Fc -j 6 -v -U $USER -d $DATABASE -n public  hivemind_public.dump;


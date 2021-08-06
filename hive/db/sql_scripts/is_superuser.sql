CREATE OR REPLACE FUNCTION is_superuser()
  RETURNS bool
  LANGUAGE sql
  STABLE
AS
$function$
	SELECT EXISTS( SELECT NULL FROM pg_catalog.pg_user WHERE usesuper=TRUE and usename=current_user )
$function$;

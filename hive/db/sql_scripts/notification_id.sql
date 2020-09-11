DROP FUNCTION IF EXISTS notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
;
CREATE OR REPLACE FUNCTION notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
RETURNS BIGINT
AS
$function$
BEGIN
RETURN CAST( _block_number as BIGINT ) << 32
    | ( _notifyType << 16 )
    | ( _id & CAST( x'00FF' as INTEGER) );
END
$function$
LANGUAGE plpgsql IMMUTABLE
;
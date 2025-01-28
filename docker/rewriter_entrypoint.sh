#!/bin/sh

# Default value for REWRITE_LOG is off, unless explicitly set to 'on'
if [ "$REWRITE_LOG" = "on" ]; then
    REWRITE_LOG="rewrite_log on;"
else
    REWRITE_LOG="# rewrite_log off;"
fi

# Use sed to replace the placeholder in the nginx template file
sed "s|\${REWRITE_LOG}|$REWRITE_LOG|g" /usr/local/openresty/nginx/conf/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf

# Start nginx
exec /usr/local/openresty/bin/openresty -g 'daemon off;'

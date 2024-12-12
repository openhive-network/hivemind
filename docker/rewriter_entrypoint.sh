#!/bin/sh

# Default value for REWRITE_LOG is off, unless explicitly set to 'on'
if [ "$REWRITE_LOG" = "on" ]; then
    REWRITE_LOG="rewrite_log on;"
else
    REWRITE_LOG="# rewrite_log off;"
fi
echo "nginx::SED;"
# Use sed to replace the placeholder in the nginx template file
sed "s|\${REWRITE_LOG}|$REWRITE_LOG|g" /home/hivemind/app/rewriter/hivemind_nginx.conf.template > /home/hivemind/app/rewriter/nginx.conf

# create the directory
# mkdir /tmp/nginx
# chown -R hivemind:hivemind /tmp/nginx
# chmod -R 700 /tmp/nginx

echo "Start nginx daemon off;"
# Start nginx
# /usr/local/openresty/bin/openresty -g 'daemon off;'
# nginx -c /home/hivemind/app/rewriter/nginx.conf -g 'daemon off;'
# /etc/init.d/nginx start

# POWŁĄCZAĆ DO DOBRZE, NAJLEPIEJ JAKO SERWIS? CHYBA 
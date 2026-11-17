#!/bin/sh
set -eu
sed "s/__NODE__/${NODE_NAME}/g" /etc/tinyproxy/tinyproxy.conf.tmpl > /tmp/tinyproxy.conf
exec tinyproxy -d -c /tmp/tinyproxy.conf

#!/bin/bash


# copy kubernetes variables to cron environment
set | grep -e ^KUBE -e ^NODENAME >>/etc/environment

# load environment (/etc/environment also used by cron jobs)
. /etc/environment

# Create OK file (for liveness probe), and start simple HTTP server
cd /tmp
echo OK >health
nohup python2 -m SimpleHTTPServer 8123 >/proc/1/fd/1 2>&1 &

# start cron
cd /usr/src/app
cron -f

#!/bin/sh
eips 1 1 "Stopping photo cycler...     " 2>/dev/null
killall screensaver_daemon.sh 2>/dev/null
rm -f /tmp/kindle_ss_hook.pid
sleep 2
eips 1 1 "                               " 2>/dev/null

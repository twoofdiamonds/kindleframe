#!/bin/sh
eips 1 1 "Stopping photo cycler...     " 2>/dev/null
touch /mnt/us/.kindleframe_disabled
initctl stop kindleframe 2>/dev/null
if [ -f /tmp/kindle_ss_hook.pid ]; then
    kill -9 $(cat /tmp/kindle_ss_hook.pid) 2>/dev/null
    rm -f /tmp/kindle_ss_hook.pid
fi
sleep 2
eips 1 1 "                               " 2>/dev/null

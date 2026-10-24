#!/bin/sh
eips 1 1 "Starting 1-min cycler...    " 2>/dev/null
killall screensaver_daemon.sh 2>/dev/null
/bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
sleep 2
eips 1 1 "                               " 2>/dev/null

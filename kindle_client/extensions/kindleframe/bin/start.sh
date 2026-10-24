#!/bin/sh
eips 1 1 "Starting photo cycler...     " 2>/dev/null
rm -f /mnt/us/.kindleframe_disabled

# Ensure Upstart autostart job is installed if not already present
if [ ! -f /etc/upstart/kindleframe.conf ]; then
    /bin/sh /mnt/us/enable_autostart.sh >/dev/null 2>&1
fi

if [ -f /tmp/kindle_ss_hook.pid ]; then
    kill -9 $(cat /tmp/kindle_ss_hook.pid) 2>/dev/null
    rm -f /tmp/kindle_ss_hook.pid
fi
/bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
sleep 2
eips 1 1 "                               " 2>/dev/null

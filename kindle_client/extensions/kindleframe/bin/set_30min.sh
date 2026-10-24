#!/bin/sh
echo 1800 > /mnt/us/cycle_interval.txt
eips 1 1 "Interval: 30 min                  " 2>/dev/null
sleep 2
eips 1 1 "                                  " 2>/dev/null

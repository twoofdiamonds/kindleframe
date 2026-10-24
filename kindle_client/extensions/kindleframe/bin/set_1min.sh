#!/bin/sh
echo 60 > /mnt/us/cycle_interval.txt
eips 1 1 "Interval: 1 min (Test)            " 2>/dev/null
sleep 2
eips 1 1 "                                  " 2>/dev/null

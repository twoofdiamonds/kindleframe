#!/bin/sh
# ==============================================================================
# Kindle Photo Frame Daemon (Simple, Reliable Hardware RTC Loop)
#
# Proven approach:
# 1. Sets RTC alarm via both powerd rtcWakeup and kernel sysfs /sys/class/rtc/
# 2. Uses sleep $INTERVAL (unblocks when CPU resumes from RTC interrupt)
# 3. Checks if Kindle is asleep (screenSaver / readyToSuspend)
# 4. If asleep, simulates wakeUp 1 + powerButton 1 to cycle screensaver
# 5. If awake (active), does nothing so it doesn't interrupt reading
# ==============================================================================

PID_FILE="/tmp/kindle_ss_hook.pid"
LOG_FILE="/mnt/us/screensaver.log"
LAST_SYNC_FILE="/tmp/kindle_last_sync_time"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

get_cycle_interval() {
    INTERVAL=1800
    if [ -f /mnt/us/cycle_interval.txt ]; then
        VAL=$(cat /mnt/us/cycle_interval.txt 2>/dev/null | tr -d '\r\n')
        if [ "$VAL" -ge 10 ] 2>/dev/null; then
            INTERVAL="$VAL"
        fi
    fi
    echo "$INTERVAL"
}

get_rtc_device() {
    for dev in /sys/class/rtc/rtc1/wakealarm /sys/class/rtc/rtc0/wakealarm; do
        if [ -e "$dev" ]; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

RTC_ALARM=$(get_rtc_device)

set_wake_alarm() {
    SECS="$1"
    # 1. Kindle powerd LIPC RTC wakeup property
    lipc-set-prop -i com.lab126.powerd rtcWakeup "$SECS" 2>/dev/null

    # 2. Kernel RTC wakealarm sysfs interface
    if [ -n "$RTC_ALARM" ] && [ -e "$RTC_ALARM" ]; then
        echo 0 > "$RTC_ALARM" 2>/dev/null
        TARGET=$(( $(date +%s) + SECS ))
        echo "$TARGET" > "$RTC_ALARM" 2>/dev/null
    fi

    # 3. rtcwake command fallback if present in busybox
    rtcwake -d /dev/rtc0 -m no -s "$SECS" 2>/dev/null || rtcwake -d /dev/rtc1 -m no -s "$SECS" 2>/dev/null
}

# Kill any previous instance
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ] && [ "$OLD_PID" -ne "$$" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
INTERVAL=$(get_cycle_interval)
log "Photo frame daemon started (PID: $$). Cycle every ${INTERVAL}s."

while true; do
    # Check if disabled
    if [ -f /mnt/us/.kindleframe_disabled ]; then
        log "Daemon disabled flag found. Exiting."
        rm -f "$PID_FILE"
        exit 0
    fi

    INTERVAL=$(get_cycle_interval)

    # Arm hardware RTC to wake CPU from suspend
    set_wake_alarm "$INTERVAL"

    # Sleep for interval. When CPU suspends, hardware RTC alarm resumes sleep.
    log "Sleeping for ${INTERVAL}s (state: $(lipc-get-prop com.lab126.powerd state 2>/dev/null))..."
    sleep "$INTERVAL"

    # Check current power state
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
    log "Timer fired (state: $STATE)"

    if [ "$STATE" = "screenSaver" ] || [ "$STATE" = "readyToSuspend" ]; then
        # Kindle is sleeping with screensaver visible.
        # Simulate: wake up -> pause -> go back to sleep
        # This makes Kindle OS naturally rotate to the NEXT screensaver photo.
        log "Cycling: waking up..."
        lipc-set-prop com.lab126.powerd wakeUp 1 2>/dev/null
        sleep 3

        log "Cycling: sending back to sleep..."
        lipc-set-prop com.lab126.powerd powerButton 1 2>/dev/null
        sleep 2

        log "Cycle complete. Next photo should now be displayed."
    else
        log "Kindle is active (state: $STATE). Skipping cycle."
    fi

    # 12-hour WiFi sync check
    NOW=$(date +%s)
    LAST_SYNC=0
    [ -f "$LAST_SYNC_FILE" ] && LAST_SYNC=$(cat "$LAST_SYNC_FILE" 2>/dev/null)
    if [ $(( NOW - LAST_SYNC )) -ge 43200 ]; then
        echo "$NOW" > "$LAST_SYNC_FILE"
        log "12 hours elapsed: launching WiFi photo sync..."
        /bin/sh /mnt/us/sync_screensavers.sh >/dev/null 2>&1 &
    fi
done

#!/bin/sh
# ==============================================================================
# Kindle Photo Frame Daemon (Simple Power-Cycle Approach)
#
# The Kindle natively rotates through bg_ss00.png, bg_ss01.png, etc. each time
# it goes to sleep. This daemon simply uses the hardware RTC alarm to wake the
# Kindle from deep suspend, then simulates a power button press cycle
# (wake -> brief pause -> sleep) so the OS naturally shows the next screensaver.
#
# If the Kindle is already awake (user is reading), it does nothing.
# ==============================================================================

PID_FILE="/tmp/kindle_ss_hook.pid"
LOG_FILE="/mnt/us/screensaver.log"

# Rotation interval in seconds (60 = 1 minute for testing)
CYCLE_INTERVAL=60

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Find active hardware RTC wakealarm interface
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
    if [ -n "$RTC_ALARM" ] && [ -e "$RTC_ALARM" ]; then
        echo 0 > "$RTC_ALARM" 2>/dev/null
        TARGET=$(( $(date +%s) + SECS ))
        echo "$TARGET" > "$RTC_ALARM" 2>/dev/null
        return 0
    fi
    # Fallback via powerd LIPC
    lipc-set-prop -i com.lab126.powerd rtcWakeup "$SECS" 2>/dev/null
    return 0
}

# Kill any previous instance
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
log "Photo frame daemon started (PID: $$). Cycle every ${CYCLE_INTERVAL}s."

while true; do
    # Read dynamic interval if updated by sync
    if [ -f /tmp/kindle_cycle_interval ]; then
        VAL=$(cat /tmp/kindle_cycle_interval 2>/dev/null)
        if [ "$VAL" -ge 10 ] 2>/dev/null; then
            CYCLE_INTERVAL="$VAL"
        fi
    fi

    # Arm hardware RTC to wake CPU from deep suspend
    set_wake_alarm "$CYCLE_INTERVAL"

    # Sleep for the interval. If CPU suspends, RTC alarm will resume execution.
    sleep "$CYCLE_INTERVAL"

    # Check current power state
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
    log "Timer fired (state: $STATE)"

    if [ "$STATE" = "screenSaver" ] || [ "$STATE" = "readyToSuspend" ]; then
        # Kindle is sleeping with screensaver visible.
        # Simulate: wake up -> tiny pause -> go back to sleep
        # This makes Kindle OS naturally show the NEXT bg_ssNN.png image.

        log "Cycling: waking up..."
        lipc-set-prop com.lab126.powerd wakeUp 1 2>/dev/null
        sleep 3

        log "Cycling: sending back to sleep..."
        lipc-set-prop com.lab126.powerd powerButton 1 2>/dev/null
        sleep 2

        log "Cycle complete. Next screensaver should now be displayed."
    else
        # Kindle is awake (user is using it). Do nothing.
        log "Kindle is active (state: $STATE). Skipping cycle."
    fi

    # Autonomous 12-hour WiFi sync
    NOW=$(date +%s)
    LAST_SYNC_FILE="/tmp/kindle_last_sync_time"
    LAST_SYNC=0
    [ -f "$LAST_SYNC_FILE" ] && LAST_SYNC=$(cat "$LAST_SYNC_FILE" 2>/dev/null)
    if [ $(( NOW - LAST_SYNC )) -ge 43200 ]; then
        echo "$NOW" > "$LAST_SYNC_FILE"
        log "12 hours elapsed: triggering WiFi sync..."
        /bin/sh /mnt/us/sync_screensavers.sh >/dev/null 2>&1 &
    fi
done

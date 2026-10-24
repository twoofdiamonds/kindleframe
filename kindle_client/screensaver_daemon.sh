#!/bin/sh
# ==============================================================================
# Kindle Photo Frame Daemon (Kernel STR Suspend-to-RAM Architecture)
#
# Proven approach:
# 1. Check if Kindle is asleep (state is screenSaver or readyToSuspend)
# 2. Arm hardware PMIC RTC (/dev/rtc1 and /dev/rtc0)
# 3. Enter kernel Suspend-to-RAM: echo "mem" > /sys/power/state
# 4. When hardware RTC alarm fires, kernel wakes up and execution resumes immediately
# 5. Cycle screensaver via wakeUp 1 + powerButton 1
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

set_wake_alarm() {
    SECS="$1"
    # 1. Direct hardware PMIC RTC on Kindle (/dev/rtc1 is PMIC, /dev/rtc0 is SoC)
    rtcwake -d /dev/rtc1 -m no -s "$SECS" 2>/dev/null || rtcwake -d /dev/rtc0 -m no -s "$SECS" 2>/dev/null

    # 2. Native Kindle powerd property
    lipc-set-prop -i com.lab126.powerd rtcWakeup "$SECS" 2>/dev/null

    # 3. Kernel sysfs wakealarm interfaces
    TARGET=$(( $(date +%s) + SECS ))
    for dev in /sys/class/rtc/rtc1/wakealarm /sys/class/rtc/rtc0/wakealarm; do
        if [ -e "$dev" ]; then
            echo 0 > "$dev" 2>/dev/null
            echo "$TARGET" > "$dev" 2>/dev/null
        fi
    done
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
log "Photo frame daemon started (PID: $$). Active interval: ${INTERVAL}s."

while true; do
    # Check if disabled
    if [ -f /mnt/us/.kindleframe_disabled ]; then
        log "Daemon disabled flag found. Exiting."
        rm -f "$PID_FILE"
        exit 0
    fi

    INTERVAL=$(get_cycle_interval)
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)

    if [ "$STATE" = "screenSaver" ] || [ "$STATE" = "readyToSuspend" ]; then
        # Device is in sleep mode: schedule hardware wake and enter Suspend-to-RAM
        log "Arming RTC for ${INTERVAL}s and entering kernel suspend (mem)..."
        set_wake_alarm "$INTERVAL"

        # Give hardware 1 second to register alarm
        sleep 1

        # Direct kernel Suspend-to-RAM. Execution halts here until RTC alarm wakes CPU!
        echo "mem" > /sys/power/state 2>/dev/null || sleep "$INTERVAL"

        # === WAKEUP POINT ===
        # The CPU just woke up from deep sleep!
        log "Woke from suspend! Verifying state..."
        sleep 2
        NEW_STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
        log "Power state after wake: $NEW_STATE"

        if [ "$NEW_STATE" = "screenSaver" ] || [ "$NEW_STATE" = "readyToSuspend" ]; then
            log "Cycling: waking up screen..."
            lipc-set-prop com.lab126.powerd wakeUp 1 2>/dev/null
            sleep 3

            log "Cycling: sending back to sleep..."
            lipc-set-prop com.lab126.powerd powerButton 1 2>/dev/null
            sleep 2

            log "Cycle complete. Next photo displayed."
        else
            log "Kindle was woken by user ($NEW_STATE). Skipping cycle."
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
    else
        # Kindle is active (user reading or in menus). Don't sleep or interrupt.
        # Wait 15 seconds and re-check if user has put Kindle to sleep.
        sleep 15
    fi
done

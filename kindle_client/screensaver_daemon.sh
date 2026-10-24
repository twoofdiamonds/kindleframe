#!/bin/sh
# ==============================================================================
# Kindle Photo Frame Daemon (Deep-Sleep Aware PowerD Event Architecture)
#
# Listens to native Amazon powerd LIPC events:
# 1. 'readyToSuspend': Fired right before the Kindle cuts CPU power for deep sleep.
#    Sets 'com.lab126.powerd rtcWakeup' so the hardware PMIC RTC wakes the CPU.
# 2. 'wakeupFromSuspend': Fired when the hardware RTC interrupt wakes the CPU.
#    If the device is still sleeping (screensaver active), simulates wake+sleep
#    to trigger the native Kindle screensaver rotation.
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
    # 1. Native Kindle powerd RTC wakeup (crucial: required for deep sleep wakeup)
    lipc-set-prop -i com.lab126.powerd rtcWakeup "$SECS" 2>/dev/null

    # 2. Kernel RTC wakealarm fallback
    if [ -n "$RTC_ALARM" ] && [ -e "$RTC_ALARM" ]; then
        echo 0 > "$RTC_ALARM" 2>/dev/null
        TARGET=$(( $(date +%s) + SECS ))
        echo "$TARGET" > "$RTC_ALARM" 2>/dev/null
    fi
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

    # 1. Check power state and handle readyToSuspend
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)

    if [ "$STATE" = "readyToSuspend" ] || [ "$STATE" = "screenSaver" ]; then
        # Already in sleep phase: arm RTC immediately
        log "Device state is $STATE. Arming RTC for ${INTERVAL}s."
        set_wake_alarm "$INTERVAL"
    else
        log "Device state is $STATE. Waiting for readyToSuspend event..."
        # Block until powerd enters readyToSuspend (or timeout after 120s)
        lipc-wait-event -s 120 com.lab126.powerd readyToSuspend 2>/dev/null
        STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
        if [ "$STATE" = "readyToSuspend" ] || [ "$STATE" = "screenSaver" ]; then
            log "readyToSuspend captured! Arming RTC for ${INTERVAL}s."
            set_wake_alarm "$INTERVAL"
        fi
    fi

    # 2. Block until hardware RTC wakes the Kindle from deep suspend
    log "Waiting for wakeupFromSuspend (entering deep sleep)..."
    lipc-wait-event com.lab126.powerd wakeupFromSuspend 2>/dev/null

    # 3. Kindle has woken from suspend!
    log "wakeupFromSuspend received! Checking device power state..."
    sleep 2
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
    log "Current state after wakeup: $STATE"

    if [ "$STATE" = "screenSaver" ] || [ "$STATE" = "readyToSuspend" ]; then
        # Device is still in screensaver mode (maintenance RTC wake)
        log "Cycling: waking screen..."
        lipc-set-prop -i com.lab126.powerd wakeUp 1 2>/dev/null
        sleep 3

        log "Cycling: sending back to sleep..."
        lipc-set-prop -i com.lab126.powerd powerButton 1 2>/dev/null
        sleep 2
        log "Cycle complete. Next photo displayed."
    else
        # User pressed power button to use the Kindle
        log "Kindle is in active use ($STATE). Skipping screensaver cycle."
    fi

    # 4. Check 12-hour WiFi sync schedule
    NOW=$(date +%s)
    LAST_SYNC=0
    [ -f "$LAST_SYNC_FILE" ] && LAST_SYNC=$(cat "$LAST_SYNC_FILE" 2>/dev/null)
    if [ $(( NOW - LAST_SYNC )) -ge 43200 ]; then
        echo "$NOW" > "$LAST_SYNC_FILE"
        log "12 hours elapsed: launching WiFi photo sync..."
        /bin/sh /mnt/us/sync_screensavers.sh >/dev/null 2>&1 &
    fi

    # Small pause before next cycle loop
    sleep 2
done

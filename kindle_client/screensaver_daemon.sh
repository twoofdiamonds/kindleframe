#!/bin/sh
# ==============================================================================
# Kindle Instagram Photo Frame & Screensaver Daemon (Hardware RTC Edition)
#
# Enables:
# 1. Immediate picture change whenever you press the lock button.
# 2. 30-minute automatic picture change while sleeping on a desk/stand:
#    Uses the Kindle's hardware Real Time Clock (RTC) chip to wake the device
#    from deep CPU suspend, update the e-ink screen, and return to sleep.
# ==============================================================================

PHOTOS_DIR="/mnt/us/screensavers"
BLANKET_DIR="/usr/share/blanket/screensaver"
STATE_FILE="/tmp/current_ss_index"
PID_FILE="/tmp/kindle_ss_hook.pid"
LOG_FILE="/mnt/us/screensaver.log"
BASE_URL="https://twoofdiamonds.github.io/kindleframe"
MANIFEST_FILE="/tmp/kindle_manifest.json"

# Rotation interval in seconds (1800 = 30 minutes)
CYCLE_INTERVAL=1800

mkdir -p "$PHOTOS_DIR"

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

set_hardware_wake_alarm() {
    INTERVAL="$1"
    if [ -n "$RTC_ALARM" ] && [ -e "$RTC_ALARM" ]; then
        # Reset previous alarm, then set target epoch time
        echo 0 > "$RTC_ALARM" 2>/dev/null
        TARGET=$(( $(date +%s) + INTERVAL ))
        echo "$TARGET" > "$RTC_ALARM" 2>/dev/null
        log "Hardware RTC alarm set for +${INTERVAL}s (target: $TARGET)"
        return 0
    fi
    # Fallback via powerd LIPC property
    lipc-set-prop -i com.lab126.powerd rtcWakeup "$INTERVAL" 2>/dev/null
    return 0
}

# Kill existing instance
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
log "Photo frame daemon started with RTC hardware alarm support (PID: $$)."

rotate_and_display() {
    ALL_PHOTOS=$(ls "$PHOTOS_DIR"/*.png 2>/dev/null | grep -v 'bg_ss')
    if [ -z "$ALL_PHOTOS" ]; then
        ALL_PHOTOS=$(ls "$PHOTOS_DIR"/*.png 2>/dev/null)
    fi

    if [ -z "$ALL_PHOTOS" ]; then
        log "No photos found in $PHOTOS_DIR."
        return 1
    fi

    COUNT=$(echo "$ALL_PHOTOS" | wc -w)
    INDEX=0
    if [ -f "$STATE_FILE" ]; then
        INDEX=$(cat "$STATE_FILE")
    fi
    INDEX=$(( (INDEX + 1) % COUNT ))
    echo "$INDEX" > "$STATE_FILE"

    PICK_NUM=$(( INDEX + 1 ))
    SELECTED=$(echo "$ALL_PHOTOS" | awk -v n="$PICK_NUM" '{print $n}')

    if [ -f "$SELECTED" ]; then
        FNAME=$(basename "$SELECTED")
        log "Displaying photo [$PICK_NUM/$COUNT]: $FNAME"

        # Prime all native screensaver slots with this photo
        IDX=0
        while [ "$IDX" -lt 20 ]; do
            PAD=$(printf "%02d" $IDX)
            cp -f "$SELECTED" "$PHOTOS_DIR/bg_ss${PAD}.png" 2>/dev/null
            if [ -d "$BLANKET_DIR" ] && [ ! -L "$BLANKET_DIR" ]; then
                cp -f "$SELECTED" "$BLANKET_DIR/bg_ss${PAD}.png" 2>/dev/null
            fi
            IDX=$((IDX + 1))
        done

        # Draw directly to e-ink screen
        eips -f -g "$SELECTED" 2>/dev/null
        return 0
    fi
    return 1
}

# Initial rotation
rotate_and_display

# Main Loop:
# 1. Catches sleep event (power button / timeout) -> rotates photo immediately.
# 2. Sets hardware RTC alarm so the Kindle hardware wakes the CPU every 30 minutes while asleep.
# 3. When alarm fires while asleep -> rotates to next photo and goes back to sleep!
while true; do
    # Read dynamic interval if updated from manifest
    if [ -f /tmp/kindle_cycle_interval ]; then
        VAL=$(cat /tmp/kindle_cycle_interval)
        if [ "$VAL" -ge 10 ] 2>/dev/null; then
            CYCLE_INTERVAL="$VAL"
        fi
    fi

    # Arm hardware RTC wakealarm
    set_hardware_wake_alarm "$CYCLE_INTERVAL"

    # Wait for either user lock event OR RTC alarm wakeup from suspend
    # This blocks until powerd signals sleep/wake/alarm
    lipc-wait-event -m -s "$CYCLE_INTERVAL" com.lab126.powerd goingToScreenSaver,resumedFromSuspend >/dev/null 2>&1

    # Check if Kindle is currently sleeping / screensaver
    STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
    
    if [ "$STATE" = "screenSaver" ] || [ "$STATE" = "readyToSuspend" ] || [ "$STATE" = "active" ]; then
        sleep 0.5
        rotate_and_display
    fi
done

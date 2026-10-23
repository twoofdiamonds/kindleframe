#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver Daemon (Firmware 5.18.1 Compatible)
#
# Listens for Kindle's native sleep event (goingToScreenSaver).
# When your Kindle goes to sleep (power button or timeout), it paints the next
# 600x800 photo from @koel.jpg directly to the screen via eips.
#
# Works on ALL Kindles (even with Special Offers / Ads).
# Consumes 0% CPU while you are reading.
# ==============================================================================

SCREENSAVERS_DIR="/mnt/us/screensavers"
STATE_FILE="/tmp/current_ss_index"
PID_FILE="/tmp/kindle_ss_hook.pid"
LOG_FILE="/mnt/us/screensaver.log"
BASE_URL="https://twoofdiamonds.github.io/kindleframe"
MANIFEST_FILE="/tmp/kindle_manifest.json"

mkdir -p "$SCREENSAVERS_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Kill previous instance if running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
log "Screensaver daemon started (PID: $$)."

sync_photos() {
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        if curl -s -k -f --connect-timeout 8 "$BASE_URL/manifest.json" -o "$MANIFEST_FILE" 2>/dev/null || \
           wget --no-check-certificate -q --timeout=8 "$BASE_URL/manifest.json" -O "$MANIFEST_FILE" 2>/dev/null; then
            
            IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')
            if [ -n "$IMAGES_LIST" ]; then
                for img in $IMAGES_LIST; do
                    if [ ! -f "$SCREENSAVERS_DIR/$img" ]; then
                        log "Downloading: $img"
                        curl -s -k -f "$BASE_URL/images/$img" -o "$SCREENSAVERS_DIR/$img" 2>/dev/null || \
                        wget --no-check-certificate -q "$BASE_URL/images/$img" -O "$SCREENSAVERS_DIR/$img" 2>/dev/null
                    fi
                done
                for f in "$SCREENSAVERS_DIR"/*.png; do
                    if [ -f "$f" ]; then
                        fname=$(basename "$f")
                        echo "$IMAGES_LIST" | grep -q "$fname" || rm -f "$f"
                    fi
                done
            fi
            rm -f "$MANIFEST_FILE"
        fi
    fi
}

show_next_screensaver() {
    PHOTOS=$(ls "$SCREENSAVERS_DIR"/*.png 2>/dev/null)
    if [ -n "$PHOTOS" ]; then
        COUNT=$(echo "$PHOTOS" | wc -w)
        INDEX=0
        if [ -f "$STATE_FILE" ]; then
            INDEX=$(cat "$STATE_FILE")
        fi
        INDEX=$(( (INDEX + 1) % COUNT ))
        echo "$INDEX" > "$STATE_FILE"

        PICK_NUM=$(( INDEX + 1 ))
        SELECTED=$(echo "$PHOTOS" | awk -v n="$PICK_NUM" '{print $n}')

        if [ -f "$SELECTED" ]; then
            log "Displaying screensaver: $(basename "$SELECTED")"
            # Small delay to ensure powerd finishes screen transition
            sleep 0.5
            eips -f -g "$SELECTED"
        fi
    fi
}

# Run initial sync if online
sync_photos

# Listen for sleep event with zero CPU consumption
log "Listening for sleep events (goingToScreenSaver)..."
lipc-wait-event -m com.lab126.powerd goingToScreenSaver | while read event; do
    show_next_screensaver
    sync_photos
done

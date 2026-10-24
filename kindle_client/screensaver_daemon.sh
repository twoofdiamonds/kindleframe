#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver & Photo Frame Daemon
#
# Fixes the stuck picture issue by:
# 1. Overwriting ALL bg_ss*.png slots with the next photo in sequence.
#    (No matter which slot the Kindle OS loads, it ALWAYS gets the new photo!)
# 2. Cycling immediately every time the Kindle goes to sleep.
# 3. Auto-cycling every 30 minutes while the Kindle rests in sleep (Photo Frame mode).
# ==============================================================================

PHOTOS_DIR="/mnt/us/screensavers"
BLANKET_DIR="/usr/share/blanket/screensaver"
STATE_FILE="/tmp/current_ss_index"
PID_FILE="/tmp/kindle_ss_hook.pid"
LOG_FILE="/mnt/us/screensaver.log"
BASE_URL="https://twoofdiamonds.github.io/kindleframe"
MANIFEST_FILE="/tmp/kindle_manifest.json"

# Rotation interval while sleeping (in seconds: 1800 = 30 minutes)
CYCLE_INTERVAL=1800

mkdir -p "$PHOTOS_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Kill any existing instance
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
log "Screensaver rotator daemon started (PID: $$)."

sync_photos_from_github() {
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        if curl -s -k -f --connect-timeout 8 "$BASE_URL/manifest.json" -o "$MANIFEST_FILE" 2>/dev/null || \
           wget --no-check-certificate -q --timeout=8 "$BASE_URL/manifest.json" -O "$MANIFEST_FILE" 2>/dev/null; then
            
            IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')
            if [ -n "$IMAGES_LIST" ]; then
                for img in $IMAGES_LIST; do
                    if [ ! -f "$PHOTOS_DIR/$img" ]; then
                        log "Downloading new photo: $img"
                        curl -s -k -f "$BASE_URL/images/$img" -o "$PHOTOS_DIR/$img" 2>/dev/null || \
                        wget --no-check-certificate -q "$BASE_URL/images/$img" -O "$PHOTOS_DIR/$img" 2>/dev/null
                    fi
                done
                for f in "$PHOTOS_DIR"/*.png; do
                    case "$(basename "$f")" in
                        bg_ss*) ;;
                        *)
                            fname=$(basename "$f")
                            echo "$IMAGES_LIST" | grep -q "$fname" || rm -f "$f"
                            ;;
                    esac
                done
            fi
            rm -f "$MANIFEST_FILE"
        fi
    fi
}

rotate_to_next_photo() {
    # Get all original photos (ignore bg_ss copies)
    ALL_PHOTOS=$(ls "$PHOTOS_DIR"/*.png 2>/dev/null | grep -v 'bg_ss')
    
    # Fallback to all pngs if none matched
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
        log "Rotating to photo [$PICK_NUM/$COUNT]: $FNAME"

        # 1. Overwrite all bg_ss00.png through bg_ss19.png with the selected photo
        # This guarantees that whatever slot Kindle OS loads, it displays this exact photo!
        IDX=0
        while [ "$IDX" -lt 20 ]; do
            PAD=$(printf "%02d" $IDX)
            cp -f "$SELECTED" "$PHOTOS_DIR/bg_ss${PAD}.png" 2>/dev/null
            if [ -d "$BLANKET_DIR" ] && [ ! -L "$BLANKET_DIR" ]; then
                cp -f "$SELECTED" "$BLANKET_DIR/bg_ss${PAD}.png" 2>/dev/null
            fi
            IDX=$((IDX + 1))
        done

        # 2. If the Kindle is currently in screensaver, immediately draw it via eips
        CURRENT_STATE=$(lipc-get-prop com.lab126.powerd state 2>/dev/null)
        if [ "$CURRENT_STATE" = "screenSaver" ] || [ "$CURRENT_STATE" = "readyToSuspend" ]; then
            eips -f -g "$SELECTED" 2>/dev/null
        fi
        return 0
    fi
    return 1
}

# Initial photo rotation
rotate_to_next_photo

# Background Loop:
# Listens for sleep events AND manages periodic auto-cycling while resting
while true; do
    # Wait for the next sleep event (blocks until you press power / close cover)
    # Timeout after CYCLE_INTERVAL so it also auto-rotates if left sleeping on a desk!
    lipc-wait-event -m -s "$CYCLE_INTERVAL" com.lab126.powerd goingToScreenSaver >/dev/null 2>&1
    
    # When triggered (either by sleep event or timer expiry):
    # Wait 0.5s for Kindle's power transition to settle, then rotate!
    sleep 0.5
    rotate_to_next_photo

    # Check for new photos from GitHub
    sync_photos_from_github
done

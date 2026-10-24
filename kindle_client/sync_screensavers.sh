#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver Sync (Kindle 10th Gen Basic - 600x800)
#
# Runs in the background via cron.
# Syncs photos from GitHub Pages directly into the Kindle screensavers folder:
#   /mnt/us/linkss/screensavers/
#
# If the Kindle is asleep or WiFi is off, it can temporarily enable WiFi,
# download the new screensavers in a few seconds, and put WiFi back to sleep.
# ==============================================================================

BASE_URL="https://twoofdiamonds.github.io/kindleframe"
SCREENSAVERS_DIR="/mnt/us/linkss/screensavers"
MANIFEST_FILE="/tmp/kindle_manifest.json"
LOG_FILE="/mnt/us/sync_screensavers.log"

# Set to 1 to temporarily wake WiFi if it is currently off, then restore it
AUTO_WIFI=1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

mkdir -p "$SCREENSAVERS_DIR"

download_file() {
    URL="$1"
    DEST="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -s -k -f --connect-timeout 10 --max-time 30 -o "$DEST" "$URL"
    else
        wget --no-check-certificate -q --timeout=10 -O "$DEST" "$URL"
    fi
}

log "Starting screensaver sync..."

# 1. Manage WiFi state
WIFI_WAS_OFF=0
if [ "$AUTO_WIFI" -eq 1 ]; then
    # Check if wireless is currently enabled
    CURRENT_WIFI=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)
    if [ "$CURRENT_WIFI" != "1" ]; then
        log "WiFi is off. Temporarily enabling WiFi..."
        WIFI_WAS_OFF=1
        lipc-set-prop com.lab126.cmd wirelessEnable 1
        
        # Wait up to 20 seconds for connection
        WAITED=0
        while [ "$WAITED" -lt 20 ]; do
            sleep 2
            WAITED=$((WAITED + 2))
            if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                log "WiFi connected after ${WAITED}s."
                break
            fi
        done
    fi
fi

# 2. Download manifest
if download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"; then
    log "Manifest downloaded successfully."

    IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')

    if [ -n "$IMAGES_LIST" ]; then
        DOWNLOAD_COUNT=0
        for img in $IMAGES_LIST; do
            if [ ! -f "$SCREENSAVERS_DIR/$img" ]; then
                log "Downloading new screensaver: $img"
                if download_file "$BASE_URL/images/$img" "$SCREENSAVERS_DIR/$img"; then
                    DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
                fi
            fi
        done

        # Extract cycle interval from manifest and save for the rotator daemon
        INTERVAL=$(grep -o '"cycle_interval_seconds": *[0-9]*' "$MANIFEST_FILE" | grep -o '[0-9]*')
        if [ -n "$INTERVAL" ]; then
            echo "$INTERVAL" > /tmp/kindle_cycle_interval
            log "Updated rotation interval to ${INTERVAL}s."
        fi

        # Prune old screensavers not in manifest
        for local_file in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$local_file" ]; then
                fname=$(basename "$local_file")
                case "$fname" in
                    bg_ss*) ;; # Skip bg_ss copies, handled below
                    *)
                        echo "$IMAGES_LIST" | grep -q "$fname"
                        if [ $? -ne 0 ]; then
                            log "Removing expired screensaver: $fname"
                            rm -f "$local_file"
                        fi
                        ;;
                esac
            fi
        done

        # Re-index active photos into bg_ss slots
        rm -f "$SCREENSAVERS_DIR"/bg_ss*.png 2>/dev/null
        IDX=0
        for f in "$SCREENSAVERS_DIR"/*.png; do
            PAD=$(printf "%02d" $IDX)
            cp -f "$f" "$SCREENSAVERS_DIR/bg_ss${PAD}.png" 2>/dev/null
            IDX=$((IDX + 1))
        done

        # Reset rotation index so new photos display right away
        rm -f /tmp/current_ss_index

        log "Sync complete. Downloaded: $DOWNLOAD_COUNT new photos, total active photos: $IDX."
    fi
    rm -f "$MANIFEST_FILE"
else
    log "Warning: Could not connect to GitHub Pages (no internet or offline)."
fi

# 3. Restore WiFi state if we turned it on
if [ "$WIFI_WAS_OFF" -eq 1 ]; then
    log "Restoring WiFi to off."
    lipc-set-prop com.lab126.cmd wirelessEnable 0
fi

log "Finished."
exit 0

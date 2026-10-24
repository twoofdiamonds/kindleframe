#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver Sync (Robust HTTPS / WiFi Edition)
# ==============================================================================

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

BASE_URL="https://twoofdiamonds.github.io/kindleframe"
SCREENSAVERS_DIR="/mnt/us/screensavers"
MANIFEST_FILE="/tmp/kindle_manifest.json"
LOG_FILE="/mnt/us/sync_screensavers.log"

AUTO_WIFI=1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

mkdir -p "$SCREENSAVERS_DIR"

# Visual feedback on Kindle e-ink screen
eips 1 1 "KindleFrame: Checking GitHub..." 2>/dev/null

download_file() {
    URL="$1"
    DEST="$2"
    # Try curl first (best HTTPS support)
    if [ -x /usr/bin/curl ] || command -v curl >/dev/null 2>&1; then
        curl -s -k -f --connect-timeout 15 -m 30 -o "$DEST" "$URL" 2>/dev/null
    elif [ -x /usr/bin/wget ] || command -v wget >/dev/null 2>&1; then
        wget -q -O "$DEST" "$URL" 2>/dev/null || wget -O "$DEST" "$URL" 2>/dev/null
    fi
    [ -s "$DEST" ]
}

log "=== Starting screensaver sync ==="

# 1. Manage WiFi state
WIFI_WAS_OFF=0
if [ "$AUTO_WIFI" -eq 1 ]; then
    CURRENT_WIFI=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)
    if [ "$CURRENT_WIFI" != "1" ]; then
        log "WiFi is off. Enabling WiFi for sync..."
        WIFI_WAS_OFF=1
        lipc-set-prop com.lab126.cmd wirelessEnable 1
        
        WAITED=0
        while [ "$WAITED" -lt 25 ]; do
            sleep 2
            WAITED=$((WAITED + 2))
            if download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"; then
                log "Connected to GitHub Pages after ${WAITED}s."
                break
            fi
        done
    fi
fi

# 2. Fetch manifest if not already fetched
if [ ! -s "$MANIFEST_FILE" ]; then
    download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"
fi

if [ -s "$MANIFEST_FILE" ]; then
    log "Manifest retrieved successfully."

    # Parse cycle interval
    INTERVAL=$(grep -o '"cycle_interval_seconds": *[0-9]*' "$MANIFEST_FILE" | grep -o '[0-9]*')
    if [ -n "$INTERVAL" ]; then
        echo "$INTERVAL" > /tmp/kindle_cycle_interval
        log "Updated cycle interval to ${INTERVAL}s."
    fi

    # Parse active images
    IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')

    if [ -n "$IMAGES_LIST" ]; then
        DOWNLOAD_COUNT=0
        for img in $IMAGES_LIST; do
            if [ ! -s "$SCREENSAVERS_DIR/$img" ]; then
                log "Downloading new photo: $img"
                eips 1 1 "Downloading: $img    " 2>/dev/null
                if download_file "$BASE_URL/images/$img" "$SCREENSAVERS_DIR/$img"; then
                    DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
                fi
            fi
        done

        # 3. Purge expired photos that are no longer in the manifest
        for local_file in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$local_file" ]; then
                fname=$(basename "$local_file")
                case "$fname" in
                    bg_ss*) ;; # Skip bg_ss copies, updated below
                    *)
                        echo "$IMAGES_LIST" | grep -q "$fname"
                        if [ $? -ne 0 ]; then
                            log "Removing old photo: $fname"
                            rm -f "$local_file"
                        fi
                        ;;
                esac
            fi
        done

        # 4. Refresh native screensaver slots (bg_ss00.png, etc.)
        rm -f "$SCREENSAVERS_DIR"/bg_ss*.png 2>/dev/null
        IDX=0
        FIRST_PHOTO=""
        for f in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$f" ]; then
                [ -z "$FIRST_PHOTO" ] && FIRST_PHOTO="$f"
                PAD=$(printf "%02d" $IDX)
                cp -f "$f" "$SCREENSAVERS_DIR/bg_ss${PAD}.png" 2>/dev/null
                IDX=$((IDX + 1))
            fi
        done

        # Reset rotation index so the new photos show next
        echo 0 > /tmp/current_ss_index

        log "Sync complete! $DOWNLOAD_COUNT downloaded, $IDX active photos."
        eips 1 1 "Sync complete ($IDX photos)!  " 2>/dev/null
        sleep 2
        eips 1 1 "                               " 2>/dev/null
    fi
    rm -f "$MANIFEST_FILE"
else
    log "Error: Unable to download manifest from $BASE_URL."
    eips 1 1 "Sync failed: no internet?    " 2>/dev/null
    sleep 3
    eips 1 1 "                               " 2>/dev/null
fi

# 5. Restore WiFi state if we enabled it
if [ "$WIFI_WAS_OFF" -eq 1 ]; then
    log "Restoring WiFi to off."
    lipc-set-prop com.lab126.cmd wirelessEnable 0
fi

log "Finished."
exit 0

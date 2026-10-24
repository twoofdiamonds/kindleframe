#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver Sync (Fast Fail / Smart Diagnostics)
# ==============================================================================

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

BASE_URL="https://twoofdiamonds.github.io/kindleframe"
SCREENSAVERS_DIR="/mnt/us/screensavers"
MANIFEST_FILE="/tmp/kindle_manifest.json"
LOG_FILE="/mnt/us/sync_screensavers.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

mkdir -p "$SCREENSAVERS_DIR"

log "=== Starting screensaver sync ==="

# Check WiFi connection
IP_CHECK=$(ifconfig wlan0 2>/dev/null | grep 'inet addr:' | awk '{print $2}' | cut -d: -f2)

if [ -z "$IP_CHECK" ]; then
    log "Error: wlan0 has no IP address (WiFi disconnected or Airplane Mode is ON)."
    eips 1 1 "WiFi not connected! Connect in Settings" 2>/dev/null
    sleep 3
    eips 1 1 "                                        " 2>/dev/null
    exit 1
fi

log "WiFi connected (IP: $IP_CHECK). Checking GitHub..."
eips 1 1 "Connecting to GitHub...        " 2>/dev/null

# Prepare modern standalone curl binary
# Note: /mnt/us is mounted noexec on Kindle FW 5.x, so binaries MUST run from /tmp or /usr/bin
CURL_BIN=""
if [ -f /mnt/us/bin/curl ]; then
    cp -f /mnt/us/bin/curl /tmp/curl 2>/dev/null
    chmod 755 /tmp/curl 2>/dev/null
    # Also install system-wide if possible
    mntroot rw 2>/dev/null
    cp -f /mnt/us/bin/curl /usr/bin/curl 2>/dev/null
    chmod 755 /usr/bin/curl 2>/dev/null
    mntroot ro 2>/dev/null
    CURL_BIN="/tmp/curl"
elif [ -x /usr/bin/curl ]; then
    CURL_BIN="/usr/bin/curl"
fi

download_file() {
    URL="$1"
    DEST="$2"
    # 1. Use modern static ARM curl (bypasses outdated Amazon SSL and noexec)
    if [ -x /tmp/curl ]; then
        /tmp/curl -s -k -f --connect-timeout 8 -m 25 -o "$DEST" "$URL" 2>/dev/null
    elif [ -n "$CURL_BIN" ] && [ -x "$CURL_BIN" ]; then
        "$CURL_BIN" -s -k -f --connect-timeout 8 -m 25 -o "$DEST" "$URL" 2>/dev/null
    elif [ -x /usr/bin/curl ]; then
        /usr/bin/curl -s -k -f --connect-timeout 8 -m 25 -o "$DEST" "$URL" 2>/dev/null
    elif command -v curl >/dev/null 2>&1; then
        curl -s -k -f --connect-timeout 8 -m 25 -o "$DEST" "$URL" 2>/dev/null
    else
        # Busybox wget fallback with strict 8s timeout so it never hangs
        wget -q -T 8 -O "$DEST" "$URL" 2>/dev/null || wget -T 8 -O "$DEST" "$URL" 2>/dev/null
    fi
    [ -s "$DEST" ]
}

# Fetch manifest
rm -f "$MANIFEST_FILE"
if download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"; then
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
                eips 1 1 "Downloading $img...    " 2>/dev/null
                if download_file "$BASE_URL/images/$img" "$SCREENSAVERS_DIR/$img"; then
                    DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
                fi
            fi
        done

        # Purge old photos not in manifest
        for local_file in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$local_file" ]; then
                fname=$(basename "$local_file")
                case "$fname" in
                    bg_ss*) ;;
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

        # Re-index active photos into bg_ss slots
        rm -f "$SCREENSAVERS_DIR"/bg_ss*.png 2>/dev/null
        IDX=0
        for f in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$f" ]; then
                PAD=$(printf "%02d" $IDX)
                cp -f "$f" "$SCREENSAVERS_DIR/bg_ss${PAD}.png" 2>/dev/null
                IDX=$((IDX + 1))
            fi
        done

        echo 0 > /tmp/current_ss_index

        log "Sync complete! $DOWNLOAD_COUNT downloaded, $IDX active photos."
        eips 1 1 "Sync complete ($IDX photos)!  " 2>/dev/null
        sleep 2
        eips 1 1 "                               " 2>/dev/null
    fi
    rm -f "$MANIFEST_FILE"
else
    log "Error: Could not download manifest from $BASE_URL."
    eips 1 1 "Sync failed: GitHub unreachable" 2>/dev/null
    sleep 3
    eips 1 1 "                               " 2>/dev/null
fi

log "Finished."
exit 0

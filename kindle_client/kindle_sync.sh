#!/bin/sh
# ==============================================================================
# Kindle Instagram Photo Frame Client (GitHub Pages Edition)
# Runs autonomously on your Kindle to fetch photos from GitHub Pages & cycle them.
# ==============================================================================

# GitHub Pages URL:
BASE_URL="https://twoofdiamonds.github.io/kindleframe"

PHOTOS_DIR="/mnt/us/photos"
MANIFEST_FILE="/tmp/kindle_manifest.json"

# Prevent Kindle from showing default sleep screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

mkdir -p "$PHOTOS_DIR"

download_file() {
    URL="$1"
    DEST="$2"
    if command -v curl >/dev/null 2>&1; then
        # -k flag ensures compatibility with SSL certificates on Kindle
        curl -s -k -f -o "$DEST" "$URL"
    else
        wget --no-check-certificate -q -O "$DEST" "$URL"
    fi
}

sync_with_server() {
    echo "Checking GitHub for new posts: $BASE_URL/manifest.json"
    if download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"; then
        echo "Manifest downloaded successfully."

        # Extract cycle interval from manifest
        INTERVAL=$(grep -o '"cycle_interval_seconds": *[0-9]*' "$MANIFEST_FILE" | grep -o '[0-9]*')
        if [ -n "$INTERVAL" ]; then
            CYCLE_INTERVAL="$INTERVAL"
        fi

        # Parse image filenames from manifest
        IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')

        if [ -n "$IMAGES_LIST" ]; then
            # 1. Download any new images that do not exist locally
            for img in $IMAGES_LIST; do
                if [ ! -f "$PHOTOS_DIR/$img" ]; then
                    echo "Downloading new image: $img"
                    download_file "$BASE_URL/images/$img" "$PHOTOS_DIR/$img"
                fi
            done

            # 2. Delete any local photos that are no longer in the manifest (2 posts prior)
            for local_file in "$PHOTOS_DIR"/*.png; do
                if [ -f "$local_file" ]; then
                    fname=$(basename "$local_file")
                    echo "$IMAGES_LIST" | grep -q "$fname"
                    if [ $? -ne 0 ]; then
                        echo "Pruning expired photo: $fname"
                        rm -f "$local_file"
                    fi
                fi
            done
        fi
        rm -f "$MANIFEST_FILE"
        return 0
    else
        echo "⚠️ Unable to reach GitHub. Falling back to current local photos."
        return 1
    fi
}

# Initial settings
CYCLE_INTERVAL=1800           # Default 30 minutes (dynamically updated from manifest)
CHECK_INTERVAL_SECONDS=43200  # 12 hours between checks
SECONDS_SINCE_LAST_SYNC=43200 # Force sync on startup
CURRENT_INDEX=0

# Main loop
while true; do
    # 1. Check GitHub every 12 hours
    if [ "$SECONDS_SINCE_LAST_SYNC" -ge "$CHECK_INTERVAL_SECONDS" ]; then
        sync_with_server
        SECONDS_SINCE_LAST_SYNC=0
    fi

    # 2. Get list of current photos in local cache
    PHOTO_FILES=$(ls "$PHOTOS_DIR"/*.png 2>/dev/null)

    if [ -n "$PHOTO_FILES" ]; then
        TOTAL=$(echo "$PHOTO_FILES" | wc -w)
        PICK_NUM=$(( (CURRENT_INDEX % TOTAL) + 1 ))
        SELECTED_PHOTO=$(echo "$PHOTO_FILES" | awk -v n="$PICK_NUM" '{print $n}')

        if [ -f "$SELECTED_PHOTO" ]; then
            echo "Displaying: $SELECTED_PHOTO"
            # Clear e-ink buffer to prevent ghosting
            eips -c
            # Draw dithered image onto the screen
            eips -g "$SELECTED_PHOTO"
        fi

        CURRENT_INDEX=$(( CURRENT_INDEX + 1 ))
    else
        echo "No photos found in $PHOTOS_DIR. Waiting for next sync..."
        eips -c
        eips 10 10 "Kindle Frame: Syncing with GitHub..."
    fi

    # 3. Low-power sleep until next picture rotation
    echo "Sleeping for $CYCLE_INTERVAL seconds..."
    if [ -e /dev/rtc1 ]; then
        rtcwake -d /dev/rtc1 -m mem -s "$CYCLE_INTERVAL"
    else
        sleep "$CYCLE_INTERVAL"
    fi

    SECONDS_SINCE_LAST_SYNC=$(( SECONDS_SINCE_LAST_SYNC + CYCLE_INTERVAL ))
done

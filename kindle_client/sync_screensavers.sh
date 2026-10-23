#!/bin/sh
# ==============================================================================
# Kindle Instagram Screensaver Sync (Kindle 10th Gen Basic - 600x800)
#
# This script does NOT run as a separate app or viewer.
# It simply syncs the 600x800 photos from your GitHub Pages repository directly
# into your Kindle's native screensaver directory (/mnt/us/linkss/screensavers).
#
# Your Kindle remains a 100% normal e-reader. Whenever you lock it or it goes
# to sleep, the Kindle natively displays one of these @koel.jpg photos!
# ==============================================================================

# GitHub Pages URL:
BASE_URL="https://twoofdiamonds.github.io/kindleframe"

# Standard MobileRead ScreenSavers Hack directory:
SCREENSAVERS_DIR="/mnt/us/linkss/screensavers"
MANIFEST_FILE="/tmp/kindle_manifest.json"

mkdir -p "$SCREENSAVERS_DIR"

download_file() {
    URL="$1"
    DEST="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -s -k -f -o "$DEST" "$URL"
    else
        wget --no-check-certificate -q -O "$DEST" "$URL"
    fi
}

echo "Checking for new @koel.jpg screensavers from GitHub Pages..."

if download_file "$BASE_URL/manifest.json" "$MANIFEST_FILE"; then
    echo "Manifest downloaded."

    # Parse image filenames from manifest
    IMAGES_LIST=$(grep -o '"images": *\[[^]]*\]' "$MANIFEST_FILE" | grep -o '"[^"]*\.png"' | tr -d '"')

    if [ -n "$IMAGES_LIST" ]; then
        # 1. Download any new screensavers into the screensavers directory
        for img in $IMAGES_LIST; do
            if [ ! -f "$SCREENSAVERS_DIR/$img" ]; then
                echo "Downloading screensaver: $img"
                download_file "$BASE_URL/images/$img" "$SCREENSAVERS_DIR/$img"
            fi
        done

        # 2. Prune old screensavers that are no longer in the manifest
        for local_file in "$SCREENSAVERS_DIR"/*.png; do
            if [ -f "$local_file" ]; then
                fname=$(basename "$local_file")
                echo "$IMAGES_LIST" | grep -q "$fname"
                if [ $? -ne 0 ]; then
                    echo "Removing expired screensaver: $fname"
                    rm -f "$local_file"
                fi
            fi
        done
        echo "Screensavers successfully synced to $SCREENSAVERS_DIR!"
    fi
    rm -f "$MANIFEST_FILE"
else
    echo "Could not reach GitHub Pages. Keeping existing screensavers."
    exit 1
fi

exit 0

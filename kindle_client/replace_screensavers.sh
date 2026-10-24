#!/bin/sh
# ==============================================================================
# Replace Default Kindle Pencil/Eraser Screensavers with @koel.jpg Photos
# ==============================================================================

BLANKET_DIR="/usr/share/blanket/screensaver"
BACKUP_DIR="/usr/share/blanket/screensaver.orig"
PHOTOS_DIR="/mnt/us/screensavers"

echo "Making root filesystem writable..."
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# 1. Back up original Amazon screensavers if not already backed up
if [ ! -d "$BACKUP_DIR" ] && [ -d "$BLANKET_DIR" ]; then
    echo "Backing up original pencils/erasers to $BACKUP_DIR..."
    cp -r "$BLANKET_DIR" "$BACKUP_DIR"
fi

mkdir -p "$PHOTOS_DIR"

# 2. Convert /usr/share/blanket/screensaver to a symlink pointing to /mnt/us/screensavers
if [ ! -L "$BLANKET_DIR" ]; then
    echo "Linking $BLANKET_DIR to $PHOTOS_DIR..."
    rm -rf "$BLANKET_DIR"
    ln -s "$PHOTOS_DIR" "$BLANKET_DIR"
fi

# 3. Kindle OS strictly looks for files named bg_ss00.png, bg_ss01.png, etc.
# Link or copy all our downloaded photos to the bg_ssNN.png format
INDEX=0
for img in "$PHOTOS_DIR"/*.png; do
    if [ -f "$img" ]; then
        PAD=$(printf "%02d" $INDEX)
        TARGET="$PHOTOS_DIR/bg_ss${PAD}.png"
        if [ "$img" != "$TARGET" ]; then
            cp -f "$img" "$TARGET"
        fi
        INDEX=$((INDEX + 1))
    fi
done

echo "✓ Converted $INDEX photos to native Kindle screensaver format."

# 4. Make filesystem read-only again
mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

# 5. Refresh Kindle UI so it re-indexes screensavers
echo "Restarting Kindle UI..."
killall cvm 2>/dev/null || restart lab126_gui 2>/dev/null

# 6. Start screensaver auto-cycle daemon in background
if [ -f /tmp/kindle_ss_hook.pid ]; then
    kill -9 $(cat /tmp/kindle_ss_hook.pid) 2>/dev/null
    rm -f /tmp/kindle_ss_hook.pid
fi
/bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &

echo "=== SUCCESS! ==="
echo "Screensaver activated with 1-minute auto-cycle!"

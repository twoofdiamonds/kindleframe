#!/bin/sh
# ==============================================================================
# Installer for Kindle Instagram Screensaver Cron Job
# Run this once on your Kindle via SSH or KUAL terminal:
#   sh /mnt/us/install_cron.sh
# ==============================================================================

SCRIPT_PATH="/mnt/us/sync_screensavers.sh"
CRON_JOB="0 */6 * * * /bin/sh $SCRIPT_PATH >/dev/null 2>&1"

echo "=== Installing Screensaver Cron Job ==="

# 1. Ensure the sync script is executable
if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
    echo "✓ Made $SCRIPT_PATH executable."
else
    echo "✗ Error: Could not find $SCRIPT_PATH. Please copy it to your Kindle root first."
    exit 1
fi

# 2. Make filesystem writable
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# 3. Determine crontab location
CRON_DIR="/etc/crontab"
if [ ! -d "$CRON_DIR" ]; then
    CRON_DIR="/var/spool/cron/crontabs"
fi
mkdir -p "$CRON_DIR"
CRON_FILE="$CRON_DIR/root"

# 4. Add the cron job if not already present
if [ -f "$CRON_FILE" ] && grep -q "sync_screensavers.sh" "$CRON_FILE"; then
    echo "✓ Cron job is already installed in $CRON_FILE."
else
    echo "$CRON_JOB" >> "$CRON_FILE"
    echo "✓ Added cron schedule (runs every 6 hours):"
    echo "  $CRON_JOB"
fi

# 5. Ensure crond daemon is running
killall crond 2>/dev/null
if [ -x /usr/sbin/crond ]; then
    /usr/sbin/crond -b -c "$CRON_DIR"
elif [ -x /bin/busybox ]; then
    busybox crond -b -c "$CRON_DIR"
fi
echo "✓ Crond service is active."

# 6. Restore filesystem to read-only
mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

# 7. Run initial sync test
echo "=== Running initial sync test ==="
/bin/sh "$SCRIPT_PATH"
echo "=== Setup complete! Check /mnt/us/sync_screensavers.log for logs. ==="

#!/bin/sh
# ==============================================================================
# Installer for Kindle Instagram Screensaver Cron & Rotator
# ==============================================================================

SYNC_PATH="/mnt/us/sync_screensavers.sh"
DAEMON_PATH="/mnt/us/screensaver_daemon.sh"
CRON_JOB="0 */6 * * * /bin/sh $SYNC_PATH >/dev/null 2>&1"
DAEMON_JOB="@reboot /bin/sh $DAEMON_PATH >/dev/null 2>&1 &"

echo "=== Installing Screensaver Automation ==="

chmod +x "$SYNC_PATH" "$DAEMON_PATH" 2>/dev/null

# 1. Make filesystem writable
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# 2. Determine crontab location
CRON_DIR="/etc/crontab"
if [ ! -d "$CRON_DIR" ]; then
    CRON_DIR="/var/spool/cron/crontabs"
fi
mkdir -p "$CRON_DIR"
CRON_FILE="$CRON_DIR/root"

# 3. Add 6-hour sync job
if ! grep -q "sync_screensavers.sh" "$CRON_FILE" 2>/dev/null; then
    echo "$CRON_JOB" >> "$CRON_FILE"
    echo "✓ Added 6-hour GitHub sync schedule."
fi

# 4. Add boot persistence for the rotator daemon
if ! grep -q "screensaver_daemon.sh" "$CRON_FILE" 2>/dev/null; then
    echo "$DAEMON_JOB" >> "$CRON_FILE"
    echo "✓ Added reboot startup for rotator daemon."
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

# 7. Start the rotator daemon right now
/bin/sh "$DAEMON_PATH" >/dev/null 2>&1 &
echo "✓ Screensaver rotator daemon started."

echo "=== Setup complete! Your screensavers will now rotate automatically. ==="

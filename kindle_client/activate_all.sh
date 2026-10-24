#!/bin/sh
# ==============================================================================
# KindleFrame All-in-One Master Activation
#
# Enables:
# 1. Instagram Photo Screensaver System (linked to /mnt/us/screensavers)
# 2. 30-Minute Automatic Photo Cycler
# 3. Permanent Auto-Start on Boot (Upstart service)
# 4. Silencing of Welcome Wizard & Cloud Nagging
# 5. Background 12-Hour WiFi Instagram Sync
# ==============================================================================

LOG_FILE="/mnt/us/screensaver.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [activate_all] $1" >> "$LOG_FILE"
}

eips 1 1 "Setting up KindleFrame...        " 2>/dev/null
log "=== Master Activation Started ==="

# 1. Set cycle interval to 30 minutes (1800s)
echo 1800 > /mnt/us/cycle_interval.txt
rm -f /mnt/us/.kindleframe_disabled
log "Interval set to 30 minutes (1800s)."

# 2. Make root filesystem writable
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# 3. Screensaver Setup
BLANKET_DIR="/usr/share/blanket/screensaver"
BACKUP_DIR="/usr/share/blanket/screensaver.orig"
PHOTOS_DIR="/mnt/us/screensavers"

mkdir -p "$PHOTOS_DIR"

if [ ! -d "$BACKUP_DIR" ] && [ -d "$BLANKET_DIR" ]; then
    cp -r "$BLANKET_DIR" "$BACKUP_DIR" 2>/dev/null
fi

if [ ! -L "$BLANKET_DIR" ]; then
    rm -rf "$BLANKET_DIR"
    ln -s "$PHOTOS_DIR" "$BLANKET_DIR"
fi

# Convert photos to bg_ssNN.png format
INDEX=0
for img in "$PHOTOS_DIR"/*.png; do
    if [ -f "$img" ]; then
        PAD=$(printf "%02d" $INDEX)
        TARGET="$PHOTOS_DIR/bg_ss${PAD}.png"
        if [ "$img" != "$TARGET" ]; then
            cp -f "$img" "$TARGET" 2>/dev/null
        fi
        INDEX=$((INDEX + 1))
    fi
done
log "Indexed $INDEX screensaver photos."

# 4. Install Permanent Upstart Boot Service
cat << 'EOF' > /etc/upstart/kindleframe.conf
description "KindleFrame Photo Cycler Daemon"

start on started lab126_gui
stop on stopping lab126_gui

respawn
respawn limit 10 120

script
    COUNT=0
    while [ ! -f /mnt/us/screensaver_daemon.sh ] && [ $COUNT -lt 30 ]; do
        sleep 2
        COUNT=$((COUNT + 1))
    done

    if [ -f /mnt/us/screensaver_daemon.sh ] && [ ! -f /mnt/us/.kindleframe_disabled ]; then
        exec /bin/sh /mnt/us/screensaver_daemon.sh
    fi
end script
EOF
chmod 644 /etc/upstart/kindleframe.conf
initctl reload-configuration 2>/dev/null
log "Upstart boot service installed."

# 5. Silence Welcome Wizard & Cloud Nags
PREFS_DIR="/var/local/java/prefs"
mkdir -p "$PREFS_DIR"
cat << 'EOF' > "$PREFS_DIR/reginfo"
user_name=Kindle
given_name=Kindle
device_name=Kindle Frame
alias=Kindle
EOF
chmod 644 "$PREFS_DIR/reginfo"

HOSTS_FILE="/etc/hosts"
for dom in firs-ta-g7g.amazon.com device-messaging.amazon.com todo-ta-g7g.amazon.com; do
    if ! grep -q "$dom" "$HOSTS_FILE" 2>/dev/null; then
        echo "127.0.0.1 $dom" >> "$HOSTS_FILE"
    fi
done

sqlite3 /var/local/appreg.db 'update properties set value = "false" where name = "whispersync.enabled";' 2>/dev/null
log "Welcome wizard and cloud nags silenced."

# 6. Make root filesystem read-only again
mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

# 7. Start / Restart the Daemon
if [ -f /tmp/kindle_ss_hook.pid ]; then
    OLD_PID=$(cat /tmp/kindle_ss_hook.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f /tmp/kindle_ss_hook.pid
fi

/bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
log "Screensaver daemon launched."

# 8. Success message on Kindle Screen
log "=== Master Activation Complete ==="
eips 1 1 "KindleFrame Activated! (30m)     " 2>/dev/null
sleep 3
eips 1 1 "                                  " 2>/dev/null

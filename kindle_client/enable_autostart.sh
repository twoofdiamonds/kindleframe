#!/bin/sh
# ==============================================================================
# Enable KindleFrame Auto-Start on Boot via Upstart
# ==============================================================================

LOG_FILE="/mnt/us/screensaver.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [autostart] $1" >> "$LOG_FILE"
}

eips 1 1 "Configuring permanent autostart... " 2>/dev/null
log "Enabling permanent autostart on boot..."

# Make root filesystem writable
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# Create Upstart job configuration
UPSTART_CONF="/etc/upstart/kindleframe.conf"
cat << 'EOF' > "$UPSTART_CONF"
description "KindleFrame Photo Cycler Daemon"

start on started lab126_gui
stop on stopping lab126_gui

respawn
respawn limit 10 120

script
    # Wait until /mnt/us is accessible
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

chmod 644 "$UPSTART_CONF"

# In case device has Kite installed
if [ -d /mnt/us/kite/onboot ]; then
    cat << 'EOF' > /mnt/us/kite/onboot/kindleframe.sh
#!/bin/sh
if [ ! -f /mnt/us/.kindleframe_disabled ]; then
    /bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
fi
EOF
    chmod +x /mnt/us/kite/onboot/kindleframe.sh
fi

# Restore filesystem to read-only
mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

# Notify upstart of changes
initctl reload-configuration 2>/dev/null

# Clear any disabled flag
rm -f /mnt/us/.kindleframe_disabled

# Ensure daemon is currently running
if [ -f /tmp/kindle_ss_hook.pid ]; then
    OLD_PID=$(cat /tmp/kindle_ss_hook.pid)
    if [ ! -d "/proc/$OLD_PID" ]; then
        /bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
    fi
else
    /bin/sh /mnt/us/screensaver_daemon.sh >/dev/null 2>&1 &
fi

log "Permanent autostart installed successfully."
sleep 2
eips 1 1 "Autostart enabled permanently!    " 2>/dev/null
sleep 2
eips 1 1 "                                  " 2>/dev/null

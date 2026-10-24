#!/bin/sh
# ==============================================================================
# Unblock Amazon Registration Servers
# ==============================================================================

echo "Making system writable..."
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# Remove blocked amazon domains from /etc/hosts
if [ -f /etc/hosts ]; then
    sed -i '/amazon.com/d' /etc/hosts
    echo "✓ Unblocked Amazon FIRS registration servers in /etc/hosts."
fi

# Remove fake reginfo so official registration can take over
rm -f /var/local/java/prefs/reginfo 2>/dev/null

mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

echo "=== SUCCESS! ==="
echo "You can now connect to WiFi and register your Kindle."

#!/bin/sh
# ==============================================================================
# Dismiss "Welcome to Kindle" & Stop "Cloud Not Connected" Popups
# ==============================================================================

echo "Making system writable..."
mntroot rw 2>/dev/null || mount -o remount,rw / 2>/dev/null

# 1. Fake local registration to dismiss the "Welcome / Set up your device" wizard
PREFS_DIR="/var/local/java/prefs"
mkdir -p "$PREFS_DIR"

cat << 'EOF' > "$PREFS_DIR/reginfo"
user_name=Kindle
given_name=Kindle
device_name=Kindle Frame
alias=Kindle
EOF
chmod 644 "$PREFS_DIR/reginfo"
echo "✓ Dismissed Welcome/Setup wizard."

# 2. Block Amazon Cloud Sync nagging servers in /etc/hosts
# This stops the background daemon from polling Amazon Cloud and popping up errors
HOSTS_FILE="/etc/hosts"
DOMAINS="firs-ta-g7g.amazon.com device-messaging.amazon.com todo-ta-g7g.amazon.com"

for dom in $DOMAINS; do
    if ! grep -q "$dom" "$HOSTS_FILE" 2>/dev/null; then
        echo "127.0.0.1 $dom" >> "$HOSTS_FILE"
    fi
done
echo "✓ Silenced Amazon Cloud sync nag servers."

# 3. Disable Whispersync in system preferences
sqlite3 /var/local/appreg.db 'update properties set value = "false" where name = "whispersync.enabled";' 2>/dev/null

# 4. Make system read-only again
mntroot ro 2>/dev/null || mount -o remount,ro / 2>/dev/null

# 5. Restart framework to apply clean state
echo "Restarting UI..."
killall cvm 2>/dev/null || restart lab126_gui 2>/dev/null

echo "=== SUCCESS! ==="
echo "Welcome screen dismissed and Cloud popups silenced."

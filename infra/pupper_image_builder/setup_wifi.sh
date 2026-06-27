#!/bin/bash -e
# setup_wifi.sh — Configure WiFi on the Pi.
# Run on the Pi (via ethernet, USB gadget, or direct connection):
#   sudo bash setup_wifi.sh "YourSSID" "YourPassword"

if [ $# -ne 2 ]; then
    echo "Usage: sudo bash setup_wifi.sh \"SSID\" \"Password\""
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash setup_wifi.sh"
    exit 1
fi

SSID="$1"
PASSWORD="$2"

# Generate PBKDF2-SHA1 hash (same as wpa_passphrase)
PSK=$(python3 -c "
import hashlib, binascii
psk = hashlib.pbkdf2_hmac('sha1', b'${PASSWORD}', b'${SSID}', 4096, 32)
print(binascii.hexlify(psk).decode())
")

cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1
update_config=1

network={
	ssid="${SSID}"
	psk=${PSK}
}
EOF

chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
rfkill unblock wifi

echo "WiFi configured for: ${SSID}"
echo "Reboot or run: sudo systemctl restart wpa_supplicant"

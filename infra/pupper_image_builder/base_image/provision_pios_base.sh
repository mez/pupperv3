#!/bin/bash -e

set -x

retry_command() {
  local cmd="$1"
  local max_attempts=20
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    echo "Attempting to run: $cmd (Attempt $((attempt + 1))/$max_attempts)"
    if eval "$cmd"; then
      echo "Command succeeded!"
      return 0
    else
      attempt=$((attempt + 1))
      echo "Attempt $attempt/$max_attempts failed. Retrying in 1 second..."
      sleep 1
    fi
  done

  echo "Command failed after $max_attempts attempts."
  return 1
}

export DEBIAN_FRONTEND=noninteractive

DEFAULT_USER=pi
if ! id "$DEFAULT_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,video,audio,dialout,plugdev,netdev,gpio,i2c,spi "$DEFAULT_USER"
fi
mkdir -p /home/$DEFAULT_USER
chown -R $DEFAULT_USER /home/$DEFAULT_USER

# Extract pre-staged pupperv3 repo into pi's home directory.
# No --strip-components: the tarball entries are already top-level dirs
# (ros2_ws/, robot/, infra/...), so they land directly under pupperv3/.
mkdir -p /home/pi/pupperv3
tar -xzf /tmp/pupperv3_src.tar.gz -C /home/pi/pupperv3
rm /tmp/pupperv3_src.tar.gz
chown -R pi:pi /home/pi/pupperv3

# Setup for Raspberry Pi 5
echo 'dtparam=spi=on' | sudo tee -a /boot/firmware/config.txt
echo 'dtparam=i2c_arm=on,i2c_arm_baudrate=100000' | sudo tee -a /boot/firmware/config.txt
echo 'usb_max_current_enable=1' | sudo tee -a /boot/firmware/config.txt

# Touchscreen overlays for the Waveshare 4" HDMI LCD (C) — these provide the
# gt911 capacitive touch controller.
#
# The 720x720 mode is set by the cmdline `video=` line below; the connector is
# force-enabled by its `D` flag; rotation + desktop mode are set by the kanshi
# profile below. The legacy hdmi_* directives that used to be here
# (hdmi_force_hotplug, config_hdmi_boost, hdmi_group, hdmi_mode, hdmi_timings)
# are pre-KMS and IGNORED by the Pi 5 firmware, so they were removed.
echo 'dtoverlay=waveshare-4dpic-3b' >> /boot/firmware/config.txt
echo 'dtoverlay=waveshare-4dpic-4b' >> /boot/firmware/config.txt
echo 'dtoverlay=waveshare-4dpic-5b' >> /boot/firmware/config.txt
echo 'start_x=0' >> /boot/firmware/config.txt
echo 'gpu_mem=128' >> /boot/firmware/config.txt

# Screen rotation
sed -i '1s/^/video=HDMI-A-1:720x720M@60D,rotate=270 /' /boot/firmware/cmdline.txt
# Remove any leftover systemd.run firstrun.sh entries
sed -i 's| systemd\.run=[^ ]*||g; s| systemd\.run_success_action=[^ ]*||g; s| systemd\.unit=[^ ]*||g' /boot/firmware/cmdline.txt

# Force the panel EDID so the display deterministically knows its 720x720 mode.
# The panel reports a cloned "Lenovo L1950wD" EDID whose real preferred timing is
# 720x720, but on slow/cold boots the live DDC read can come back empty — then
# the desktop defaults to 1024x768, which this panel can't sync (blank screen).
# This baked-in copy is loaded by the kernel regardless of the live read.
install -d /lib/firmware/edid
base64 -d > /lib/firmware/edid/pupper-panel.bin <<'EDID_B64'
AP///////wAwroYQAQEBASIVAQOAKRp47uW1o1VJmScTUFQgAAABAQEBAQEBAQEBAQEBAQEBMBHQ
ACHQIiBkUCQE//8AAAAcAAAA/ABMRU4gTDE5NTB3RAogAAAA/QAyTB5RDgAKICAgICAgAAAA/wBC
MzQzMjg0NQogICAgAXgCAxRxQQAjCQcHgwEAAGUDDAAQAAAAABAAQDEgDEBVALmIIQAAGAAAABAA
HBYgWCwlALmIIQAAngAAABAAHBYgECwlgLmIIQAAngAAABAAMDAKICAgICAgICAgIAAAABAAOC1A
ECxFgLmIIQAAHgAAAAAAAAAAAAAAAAAAAAAA+Q==
EDID_B64
sed -i '1s/^/drm.edid_firmware=HDMI-A-1:edid\/pupper-panel.bin /' /boot/firmware/cmdline.txt

# Desktop (Wayland) output mode + rotation. The cmdline video= above only sets
# the *console*; the labwc compositor picks its own mode via kanshi and ignores
# it. The 720x720 panel has no EDID, so without this kanshi profile the desktop
# defaults to 1024x768 — which the panel can't sync, leaving it blank.
install -d -o pi -g pi /home/pi/.config/kanshi
cat > /home/pi/.config/kanshi/config <<'KANSHI'
profile {
    output HDMI-A-1 mode 720x720 transform 270 position 0,0
}
KANSHI
chown pi:pi /home/pi/.config/kanshi/config

# Rotate the Goodix touchscreen to match the 270-degree display rotation. Without
# this, the display is rotated but the touch is the identity matrix, so taps are
# transposed on the square 720x720 panel and miss their targets.
cat > /etc/udev/rules.d/99-pupper-touch-rotate.rules <<'TOUCHRULE'
SUBSYSTEM=="input", ATTRS{name}=="Goodix Capacitive TouchScreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
TOUCHRULE

# Game controller: load joydev at boot so a paired gamepad gets a /dev/input/js*
# node (the neural_controller launch's joy_linux_node reads /dev/input/js0).
# Without it, controllers register only as evdev and teleop sees no joystick.
echo joydev > /etc/modules-load.d/joydev.conf

# HiFiBerry DAC speaker
echo 'dtoverlay=hifiberry-dac' >> /boot/firmware/config.txt

# Download Waveshare display overlays
retry_command "wget 'https://files.waveshare.com/wiki/4inch%20HDMI%20LCD%20(C)/4HDMIB_DTBO.zip' -O 4HDMIB_DTBO.zip"
sudo apt install -y unzip
unzip 4HDMIB_DTBO.zip
sudo cp 4HDMIB_DTBO/*.dtbo /boot/firmware/overlays/
rm -r 4HDMIB_DTBO 4HDMIB_DTBO.zip

# Networking and SSH
sudo apt install -y avahi-daemon net-tools openssh-server curl network-manager
systemctl enable ssh
systemctl enable avahi-daemon
systemctl enable NetworkManager

# GPIO / I2C / Python tools
sudo apt install -y python-is-python3 python3-pip i2c-tools libgpiod-dev python3-libgpiod

# Bluetooth
sudo apt install -y bluez

# Audio
sudo apt install -y portaudio19-dev python3-pyaudio alsa-utils
# Set HiFiBerry DAC as default audio output (card 0 is typically the DAC with hifiberry overlay)
cat > /etc/asound.conf << 'EOF'
defaults.pcm.card 0
defaults.ctl.card 0
EOF

# General tools
sudo apt install -y vim nano

# Update all packages
export APT_LISTCHANGES_FRONTEND=none
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

sudo apt-get update
apt-get -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  upgrade

rm -f /usr/sbin/policy-rc.d

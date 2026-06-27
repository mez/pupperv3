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

# Setup for Raspberry Pi 5
echo 'dtparam=spi=on' | sudo tee -a /boot/firmware/config.txt
echo 'dtparam=i2c_arm=on,i2c_arm_baudrate=100000' | sudo tee -a /boot/firmware/config.txt
echo 'usb_max_current_enable=1' | sudo tee -a /boot/firmware/config.txt

# Touchscreen and HDMI (Waveshare 4" HDMI LCD (C))
echo 'dtoverlay=waveshare-4dpic-3b' >> /boot/firmware/config.txt
echo 'dtoverlay=waveshare-4dpic-4b' >> /boot/firmware/config.txt
echo 'dtoverlay=waveshare-4dpic-5b' >> /boot/firmware/config.txt
echo 'hdmi_force_hotplug=1' >> /boot/firmware/config.txt
echo 'config_hdmi_boost=10' >> /boot/firmware/config.txt
echo 'hdmi_group=2' >> /boot/firmware/config.txt
echo 'hdmi_mode=87' >> /boot/firmware/config.txt
echo 'hdmi_timings=720 0 100 20 100 720 0 20 8 20 0 0 0 60 0 48000000 6' >> /boot/firmware/config.txt
echo 'start_x=0' >> /boot/firmware/config.txt
echo 'gpu_mem=128' >> /boot/firmware/config.txt

# Screen rotation
sed -i '1s/^/video=HDMI-A-1:720x720M@60D,rotate=270 /' /boot/firmware/cmdline.txt

# HiFiBerry DAC speaker
echo 'dtoverlay=hifiberry-dac' >> /boot/firmware/config.txt

# Download Waveshare display overlays
retry_command "wget 'https://files.waveshare.com/wiki/4inch%20HDMI%20LCD%20(C)/4HDMIB_DTBO.zip' -O 4HDMIB_DTBO.zip"
sudo apt install -y unzip
unzip 4HDMIB_DTBO.zip
sudo cp 4HDMIB_DTBO/*.dtbo /boot/firmware/overlays/
rm -r 4HDMIB_DTBO 4HDMIB_DTBO.zip

# Networking and SSH
sudo apt install -y avahi-daemon net-tools openssh-server curl

# GPIO / I2C / Python tools
sudo apt install -y python-is-python3 python3-pip i2c-tools libgpiod-dev python3-libgpiod
sudo rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
pip install Adafruit-Blinka RPi.GPIO

# Bluetooth
sudo apt install -y bluez

# Audio
sudo apt install -y portaudio19-dev python3-pyaudio alsa-utils
pip install --upgrade pyaudio deepgram-sdk

# General tools
sudo apt install -y software-properties-common vim

# Update all packages
export APT_LISTCHANGES_FRONTEND=none
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

sudo apt-get update
apt-get -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  upgrade

rm -f /usr/sbin/policy-rc.d

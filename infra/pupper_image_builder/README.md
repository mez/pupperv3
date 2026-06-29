# Pupper V3 Image Builder

Builds a hardware-ready base image for the Raspberry Pi 5. The image includes all hardware overlays, drivers, and system configuration — but **no ROS2 or robot software**. Those are installed post-boot via the provided scripts, giving you flexibility to choose your setup path.

## What's in the base image

- PiOS Trixie (Debian 13) arm64
- SSH enabled on first boot
- Default user: `pi` / password: `pupper123`
- Waveshare 4" HDMI touchscreen overlays + display config
- HiFiBerry DAC audio overlay
- SPI, I2C, GPIO configured
- Hailo AI HAT support (`hailo-all`)
- Avahi mDNS (`pupper.local`)
- Bluetooth, audio system packages

## Setup paths

### Option A — Quick start (recommended)

Flash the pre-built image, boot, connect via SSH, then run the install script:

```bash
ssh pi@pupper.local         # password: pupper123
sudo bash install_ros.sh    # sets up the ROS2 Jazzy env (RoboStack/pixi) + clones deps
bash build_ros.sh           # builds the colcon workspace (~30-60 min; no sudo needed)
sudo bash install_ai.sh     # optional: adds Rust, GUI, LiveKit voice agent
```

> ROS 2 Jazzy is installed via [RoboStack](https://robostack.github.io/) (conda/pixi),
> not apt: Trixie ships Python 3.13 but Jazzy's apt packages target Python 3.12.
> The env is defined in `ros2_ws/pixi.toml`.

### Option B — Step by step (learning / customization)

Use `install_ros.sh` as a reference guide and run each section manually. This is the recommended path if you want to understand what's being installed.

### Option C — Build your own image

Build the base image yourself using Packer:

**Requirements:** Docker, macOS or Linux

```bash
cd infra/pupper_image_builder
bash make_image.sh
```

This downloads the Trixie base image (~1.3GB), strips the `orphan_file` ext4 feature for compatibility with the packer build tool, and builds `pupOS_pios_base_<git-hash>.img`.

Then flash to USB/SD:
```bash
# Replace diskN with your device from: diskutil list
sudo dd if=pupOS_pios_base_*.img of=/dev/rdiskN bs=4m status=progress
```

## WiFi setup

WiFi is not configured in the image. After first boot (via ethernet or USB), run:

```bash
sudo bash setup_wifi.sh "YourSSID" "YourPassword"
sudo reboot
```

## File structure

```
infra/pupper_image_builder/
  make_image.sh               # builds the base image
  setup_wifi.sh               # post-boot WiFi configuration
  sync_from_pi.sh             # dev: pull live edits off the Pi into this repo (run on WSL host)
  base_image/
    pios_base_arm64.pkr.hcl   # Packer config
    provision_pios_base.sh    # hardware provisioning script
    resources/firstrun.sh     # first-boot user/hostname/SSH setup
  install_scripts/
    install_ros.sh             # post-boot: ROS2 Jazzy env via RoboStack/pixi + source deps
    build_ros.sh               # post-boot: build the colcon workspace
    install_ai.sh              # post-boot: Rust + pupper-rs GUI + LiveKit
```

The ROS env is defined in `ros2_ws/pixi.toml` (channels, ROS desktop, build tasks).

## Default credentials

| | |
|---|---|
| Hostname | `pupper.local` |
| Username | `pi` |
| Password | `pupper123` |

**Change the password after first boot:** `passwd`

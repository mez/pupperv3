#!/bin/bash -e
# install_ros.sh — Run on the Pi (Raspberry Pi OS Trixie) after first boot to set
# up the ROS 2 Jazzy *environment*. It does NOT build the workspace — run
# build_ros.sh for that.
#
# Usage: sudo bash install_ros.sh
#
# Why RoboStack/pixi instead of `apt install ros-jazzy-desktop`?
#   Trixie ships Python 3.13 only. Jazzy's Ubuntu-Noble .debs are built for
#   Python 3.12 (not installable on Trixie), so the old apt approach is broken
#   on this host. RoboStack provides Jazzy via conda with a matched Python.
#   The env is defined declaratively in ros2_ws/pixi.toml.
#
# Privilege model: apt + the Hailo driver need root; pixi is per-user, so the
# conda/pixi work runs as $DEFAULT_USER.

set -x
# Explicit, because `sudo bash install_ros.sh` ignores the shebang's -e.
set -e
set -o pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash install_ros.sh"
    exit 1
fi

DEFAULT_USER=${SUDO_USER:-pi}
HOME_DIR="/home/$DEFAULT_USER"
WS="$HOME_DIR/pupperv3/ros2_ws"
COMMON="$WS/src/common"

export DEBIAN_FRONTEND=noninteractive

################################ System packages (root) ################################
# Hailo's kernel driver + firmware live on the HOST regardless of how ROS is
# installed; the matching pyhailort userspace goes into the pixi env later.
apt-get update
# portaudio19-dev + python3-dev: to compile pyaudio (no conda/aarch64 wheel)
#   against the system portaudio in the per-user step below.
# libcamera-dev + libcap-dev: camera_ros builds against the SYSTEM libcamera (the
#   Raspberry Pi fork has the imx296/PiSP pipeline; conda's doesn't). Usually
#   already on the Pi OS image, but pinned here for reproducibility.
apt-get install -y curl git git-lfs portaudio19-dev python3-dev libcamera-dev libcap-dev

# Non-interactively keep existing config files. (Avoid `yes N | apt ...`: under
# `set -o pipefail`, yes dies of SIGPIPE and would falsely fail the pipeline.)
apt-get full-upgrade -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef
apt-get install -y hailo-all

# Source deps live under the user's workspace. Create the dir and ensure it's
# user-owned — earlier root-run clones leave it root-owned, which blocks the
# per-user git/pixi steps below.
mkdir -p "$COMMON"
chown -R "$DEFAULT_USER:$DEFAULT_USER" "$COMMON"

################################ ROS env + workspace sources (user) ################################
# Everything below is per-user: pixi installs to ~/.pixi, the env to ros2_ws/.pixi.
sudo -u "$DEFAULT_USER" -H bash -e <<USEREOF
set -x
export PATH="\$HOME/.pixi/bin:\$PATH"

retry() { local n=0; until "\$@"; do n=\$((n+1)); [ \$n -ge 20 ] && { echo "giving up after \$n attempts"; return 1; }; echo "attempt \$n failed, retrying in 1s..."; sleep 1; done; }

# --- Install pixi (no-op if already present) ---
command -v pixi >/dev/null 2>&1 || curl -fsSL https://pixi.sh/install.sh | bash
export PATH="\$HOME/.pixi/bin:\$PATH"

# --- Clone workspace source deps into src/common/ ---
mkdir -p "$COMMON"
cd "$COMMON"
for repo in \
    https://github.com/facontidavide/rosx_introspection.git \
    https://github.com/christianrauch/camera_ros.git \
    https://github.com/ros-perception/vision_msgs.git ; do
    name=\$(basename "\$repo" .git)
    [ -d "\$name/.git" ] || retry git clone "\$repo" --recurse-submodules
done
# These are NOT built from source — we use conda's prebuilt packages instead
# (see pixi.toml): topic_tools mis-links its *Node executables when built
# standalone, and foxglove-sdk's foxglove_bridge breaks on modern asio/websocketpp.
rm -rf topic_tools foxglove-sdk

# --- Pin source deps to known-good commits ---
git config --global --add safe.directory "$COMMON/rosx_introspection"
git -C "$COMMON/rosx_introspection" checkout 3922e2c                              # older commit avoids GTest errors

# --- Materialize the Jazzy env (downloads ROS — slow, ~GBs) ---
cd "$WS"
retry pixi install -e jazzy

# --- pyaudio: no conda/aarch64 wheel. Build from PyPI against the system
# portaudio (apt portaudio19-dev). Use the *absolute* system gcc (/usr/bin/gcc):
# bare `gcc` resolves to the conda env's gcc shim, which applies conda's
# --sysroot and mixes glibc headers ('fatal error: bits/timesize.h'). Also clear
# the conda CFLAGS/LDFLAGS + override LDSHARED so the conda sysroot can't leak in.
# All scoped to this one pip build, not the ROS/colcon builds.
pixi run -e jazzy bash -c 'CC=/usr/bin/gcc CXX=/usr/bin/g++ LDSHARED="/usr/bin/gcc -shared" CFLAGS= CPPFLAGS= LDFLAGS= pip install pyaudio'

# --- pyhailort: NOT on PyPI, and apt's python3-hailort is built for the system
# Python (cp313) while this env is cp312. Build the cp312 binding from source
# against the INSTALLED libhailort, matching its EXACT version (HailoRT requires
# firmware/driver/libhailort/pyhailort all in lockstep). Skipped if no Hailo.
HAILO_VER=\$(dpkg-query -W -f='\${Version}' hailort 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ -n "\$HAILO_VER" ]; then
    echo "Building pyhailort cp312 for HailoRT \$HAILO_VER..."
    rm -rf /tmp/hailort-src
    retry git clone --depth 1 --branch "v\$HAILO_VER" https://github.com/hailo-ai/hailort.git /tmp/hailort-src
    HB=/tmp/hailort-src/hailort/libhailort
    # setup.py forwards only an allowlist of env vars to cmake — let the policy
    # override through (the bundled pybind11 declares cmake_minimum_required <3.5).
    sed -i 's/"LIBHAILORT_PATH",/"LIBHAILORT_PATH",\n        "CMAKE_POLICY_VERSION_MINIMUM",/' "\$HB/bindings/python/platform/setup.py"
    ( cd "\$HB/bindings/python/platform" && \
      LIBHAILORT_PATH=/usr/lib/libhailort.so HAILORT_INCLUDE_DIR="\$HB/include" \
      CMAKE_BUILD_TYPE=Release CMAKE_POLICY_VERSION_MINIMUM=3.5 \
      pixi run -e jazzy pip install . --no-deps )
    rm -rf /tmp/hailort-src
else
    echo "Hailo (hailort) not installed — skipping pyhailort build."
fi
USEREOF

echo ""
echo "ROS 2 Jazzy environment ready (RoboStack/pixi). Workspace NOT built yet."
echo "Next: bash build_ros.sh   (no sudo needed — the build is per-user)"

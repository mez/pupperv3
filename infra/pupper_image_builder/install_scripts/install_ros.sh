#!/bin/bash -e
# install_ros.sh — Run on the Pi after first boot to install ROS2 and build the workspace.
# Usage: sudo bash install_ros.sh
#   Optional: GITHUB_TOKEN=ghp_xxx sudo -E bash install_ros.sh

set -x

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash install_ros.sh"
    exit 1
fi

DEFAULT_USER=${SUDO_USER:-pi}
HOME_DIR=/home/$DEFAULT_USER

# Handle optional GitHub token for private repo access
GIT_ASKPASS_SCRIPT=""
GITHUB_TOKEN_CONFIGURED=false

cleanup_github_credentials() {
    if [ -n "${GIT_ASKPASS_SCRIPT:-}" ] && [ -f "${GIT_ASKPASS_SCRIPT}" ]; then
        rm -f "${GIT_ASKPASS_SCRIPT}"
    fi
    unset GIT_ASKPASS_SCRIPT GIT_ASKPASS GIT_TERMINAL_PROMPT GITHUB_TOKEN
    GITHUB_TOKEN_CONFIGURED=false
}

if [ -n "${GITHUB_TOKEN:-}" ]; then
    GITHUB_TOKEN_CONFIGURED=true
    GIT_ASKPASS_SCRIPT=$(mktemp /tmp/git-askpass-XXXXXX.sh)
    cat <<'EOF' > "${GIT_ASKPASS_SCRIPT}"
#!/bin/sh
case "$1" in
  Username*) echo "x-access-token" ;;
  Password*) echo "${GITHUB_TOKEN}" ;;
  *) echo "${GITHUB_TOKEN}" ;;
esac
EOF
    chmod 700 "${GIT_ASKPASS_SCRIPT}"
    export GIT_ASKPASS="${GIT_ASKPASS_SCRIPT}"
    export GIT_TERMINAL_PROMPT=0
    trap cleanup_github_credentials EXIT
fi

retry_command() {
    local cmd="$1"
    local max_attempts=20
    local attempt=0
    until eval "$cmd" || [ $attempt -ge $max_attempts ]; do
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts failed. Retrying in 1 second..."
        sleep 1
    done
    if [ $attempt -ge $max_attempts ]; then
        echo "Command failed after $max_attempts attempts."
        return 1
    fi
}

export DEBIAN_FRONTEND=noninteractive

################################ Install ROS2 Jazzy ################################
# ROS2 Jazzy is the latest LTS (supported until May 2029)
# Using the Ubuntu Noble (24.04) package suite — compatible with PiOS Bookworm arm64

apt-get install -y curl gnupg
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc \
  | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu noble main" \
  | tee /etc/apt/sources.list.d/ros2.list > /dev/null

apt-get update
apt-get install -y ros-jazzy-desktop

sudo rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
pip install vcstool colcon-common-extensions

echo "source /opt/ros/jazzy/setup.bash" >> "$HOME_DIR/.bashrc"
source /opt/ros/jazzy/setup.bash

################################ Install Hailo ################################
yes N | DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
apt-get install -y hailo-all

################################ Clone monorepo ################################
apt-get install -y git git-lfs

cd "$HOME_DIR"
rm -rf pupperv3
retry_command "git clone https://github.com/mez/pupperv3.git --recurse-submodules"
cd "$HOME_DIR/pupperv3"
git config --global --add safe.directory "$HOME_DIR/pupperv3"
git lfs install
git lfs pull
chown -R "$DEFAULT_USER:$DEFAULT_USER" "$HOME_DIR/pupperv3"

################################ Python deps ################################
pip install wandb sounddevice pydub pyaudio black supervision opencv-python loguru pandas
pip install Adafruit-Blinka RPi.GPIO
pip install "numpy<2" "opencv-python" "pyzmq"
pip install typeguard
pip uninstall -y em || true
pip install empy==3.3.4

################################ ROS2 source deps ################################
mkdir -p "$HOME_DIR/pupperv3/ros2_ws/src/common"
cd "$HOME_DIR/pupperv3/ros2_ws/src/common"

apt-get install -y libcap-dev libwebsocketpp-dev nlohmann-json3-dev libcamera-dev

repos=(
    "https://github.com/facontidavide/rosx_introspection.git"
    "https://github.com/foxglove/foxglove-sdk.git"
    "https://github.com/christianrauch/camera_ros.git"
    "https://github.com/ros-perception/vision_msgs.git"
)
for repo in "${repos[@]}"; do
    retry_command "git clone $repo --recurse-submodules"
done

# Pin foxglove-sdk — commit before ament_index_cpp/version.h was required (Mar 5 2026 broke Jazzy builds)
git config --global --add safe.directory "$HOME_DIR/pupperv3/ros2_ws/src/common/foxglove-sdk"
cd "$HOME_DIR/pupperv3/ros2_ws/src/common/foxglove-sdk"
git checkout 854ac57892da4c7171513ebc7dcb09ba5f63f9a3

# Pin rosx_introspection — older commit avoids GTest errors
git config --global --add safe.directory "$HOME_DIR/pupperv3/ros2_ws/src/common/rosx_introspection"
cd "$HOME_DIR/pupperv3/ros2_ws/src/common/rosx_introspection"
git checkout 3922e2c

cd "$HOME_DIR/pupperv3/ros2_ws/src/common"
retry_command "git clone https://github.com/ros-tooling/topic_tools.git --branch jazzy --recurse-submodules"

if [ "$GITHUB_TOKEN_CONFIGURED" = true ]; then
    cleanup_github_credentials
    trap - EXIT
fi

################################ Build workspace ################################
cd "$HOME_DIR/pupperv3/ros2_ws"
source /opt/ros/jazzy/setup.bash

# Step 1: Build all packages except neural_controller (OOM) and vision_msgs_rviz_plugins (API break)
tmpfile=$(mktemp /tmp/ros2-build-output.XXXXXX)
if ! colcon build --symlink-install \
    --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DPython3_EXECUTABLE=/usr/bin/python3 -DCMAKE_CXX_FLAGS="-g0" \
    --packages-skip neural_controller vision_msgs_rviz_plugins \
    2>&1 | tee "$tmpfile"; then
    echo "colcon build (step 1) failed" >&2
    rm -f "$tmpfile"
    exit 1
fi
if grep -qi 'failed' "$tmpfile"; then
    echo "colcon build (step 1) reported failures" >&2
    rm -f "$tmpfile"
    exit 1
fi
rm -f "$tmpfile"

# Step 2: Build neural_controller alone — heavy Eigen/RTNeural templates cause OOM when parallel
tmpfile=$(mktemp /tmp/ros2-build-output.XXXXXX)
if ! colcon build --symlink-install \
    --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DPython3_EXECUTABLE=/usr/bin/python3 -DCMAKE_CXX_FLAGS="-g0" \
    --packages-select neural_controller \
    --parallel-workers 1 \
    -- --cmake-args -DCMAKE_BUILD_PARALLEL_LEVEL=1 \
    2>&1 | tee "$tmpfile"; then
    echo "colcon build (neural_controller) failed" >&2
    rm -f "$tmpfile"
    exit 1
fi
if grep -qi 'failed' "$tmpfile"; then
    echo "colcon build (neural_controller) reported failures" >&2
    rm -f "$tmpfile"
    exit 1
fi
rm -f "$tmpfile"

echo "source $HOME_DIR/pupperv3/ros2_ws/install/local_setup.bash" >> "$HOME_DIR/.bashrc"

chown -R "$DEFAULT_USER:$DEFAULT_USER" "$HOME_DIR"

echo ""
echo "ROS2 Jazzy installed and workspace built successfully."
echo "Run 'source ~/.bashrc' or open a new terminal to use ROS2."
echo "Next step (optional): sudo bash install_ai.sh"

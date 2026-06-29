#!/bin/bash -e
# build_ros.sh — Build the colcon workspace inside the RoboStack pixi env.
# Run AFTER install_ros.sh.
#
# Usage: bash build_ros.sh        <- no sudo needed; the build is per-user (pixi).
#        sudo bash build_ros.sh   <- also works (drops to the user internally).
#
# Split out from install_ros.sh so the workspace can be rebuilt without
# re-installing the ROS env, and so env vs. build failures stay separate.

set -x
# Explicit, because `sudo bash build_ros.sh` ignores the shebang's -e. pipefail
# is essential: build_step pipes colcon through `tee`, and without it the `if !`
# check would see tee's exit status (0), masking build failures.
set -e
set -o pipefail

# pixi is per-user; resolve the real user whether invoked via sudo or directly.
DEFAULT_USER=${SUDO_USER:-$(id -un)}
HOME_DIR="/home/$DEFAULT_USER"
WS="$HOME_DIR/pupperv3/ros2_ws"
PIXI="$HOME_DIR/.pixi/bin/pixi"

if [ ! -x "$PIXI" ]; then
    echo "pixi not found at $PIXI — run install_ros.sh first." >&2
    exit 1
fi

# Run a command as the env owner (handles both `sudo bash ...` and plain `bash ...`).
run_as_user() {
    if [ "$(id -un)" = "$DEFAULT_USER" ]; then
        bash -c "$*"
    else
        sudo -u "$DEFAULT_USER" -H bash -c "$*"
    fi
}

# colcon can exit 0 while a package failed — also grep the output for failures.
build_step() {
    local label="$1" task="$2"
    local log; log=$(mktemp /tmp/ros2-build-XXXXXX)
    if ! run_as_user "cd '$WS' && '$PIXI' run -e jazzy $task" 2>&1 | tee "$log"; then
        echo "colcon build ($label) failed" >&2; rm -f "$log"; exit 1
    fi
    if grep -qi 'failed' "$log"; then
        echo "colcon build ($label) reported failures" >&2; rm -f "$log"; exit 1
    fi
    rm -f "$log"
}

# Step 1: all packages except neural_controller (OOM), vision_msgs_rviz_plugins
# (API break), pupper_mujoco_sim (sim-only), and camera_ros (built next).
build_step "step 1" build
# Step 2: camera_ros against the SYSTEM libcamera (Pi imx296/PiSP pipeline).
build_step "camera_ros" build-camera
# Step 3: neural_controller alone, single-threaded.
build_step "neural_controller" build-neural

# Convenience: `pupper-ros` drops into the built ROS env in interactive shells.
if ! grep -q 'pupper-ros' "$HOME_DIR/.bashrc" 2>/dev/null; then
    cat >> "$HOME_DIR/.bashrc" <<EOF

# pupperv3 ROS 2 (RoboStack/pixi). Run 'pupper-ros' for a ready ROS shell.
alias pupper-ros='cd $WS && $PIXI shell -e jazzy'
EOF
    [ "$(id -u)" -eq 0 ] && chown "$DEFAULT_USER:$DEFAULT_USER" "$HOME_DIR/.bashrc"
fi

echo ""
echo "Workspace built. Run 'pupper-ros' (new shell) for a ROS 2 environment."
echo "Next step (optional): sudo bash install_ai.sh"

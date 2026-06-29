#!/usr/bin/env bash
# sync_from_pi.sh — Run on the WSL dev host to pull source changes made live on
# the Trixie Pi back into this git repo for review & commit.
#
# The Pi was flashed from this repo; we edit files directly on the Pi under
# $PI_REPO, then rsync just the touched *source* files (not build artifacts /
# conda envs / LFS blobs) back here.
#
# Usage (from WSL, inside the repo):
#   bash infra/pupper_image_builder/sync_from_pi.sh
#
# PI_SSH is an ssh target — an ~/.ssh/config alias (recommended; carries user,
# host, key, port) or a plain user@host. Override any default via env var:
#   PI_SSH=192.168.1.50 bash infra/pupper_image_builder/sync_from_pi.sh
#
# First-time bootstrap (before this script exists locally):
#   scp pupper:/home/pi/pupperv3/infra/pupper_image_builder/sync_from_pi.sh /tmp/
#   bash /tmp/sync_from_pi.sh
#
PI_SSH="${PI_SSH:-pupper}"
PI_REPO="${PI_REPO:-/home/pi/pupperv3}"
LOCAL_REPO="${LOCAL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || echo /home/mez/codebase/pupperv3)}"

set -euo pipefail

# Source paths we are changing for the Trixie/RoboStack migration.
# Add entries here as we touch more files. Missing paths are skipped silently.
PATHS=(
  .gitignore
  infra/pupper_image_builder/install_scripts/install_ros.sh
  infra/pupper_image_builder/install_scripts/build_ros.sh
  infra/pupper_image_builder/sync_from_pi.sh
  infra/pupper_image_builder/make_image.sh
  infra/pupper_image_builder/base_image/provision_pios_base.sh
  infra/pupper_image_builder/README.md
  ros2_ws/pixi.toml
  ros2_ws/pixi.lock
  ros2_ws/src/neural_controller/launch/launch.py
  ros2_ws/src/neural_controller/launch/config.yaml
  robot/utils/robot.service
  robot/utils/robot.sh
  robot/utils/battery_monitor.service
  robot/services/volume-max.service
  robot/services/set_audio_default.sh
  pupper-rs/pupper-gui.service
  ai/llm-ui/agent-starter-python/llm-agent.service
  README.md
  pupper-rs/run_gui.sh
  robot/start_ui.sh
  ros2_ws/src/openai_bridge/openai_bridge/ros_node.py
  ros2_ws/src/pupper_feelings/pupper_feelings/face_control_gui.py
  ros2_ws/src/hailo/hailo/hailo_depth.py
  ros2_ws/src/llm_websocket_server/llm_websocket_server/websocket_server.py
  ai/playground/undistory/main.py
  ai/playground/undistory/serve_viewer.py
  ai/playground/image-description-benchmark/src/image_description_benchmark/gemini_test.py
  analysis/histogram.py
)

echo ">> Pulling ${#PATHS[@]} path(s) from ${PI_SSH}:${PI_REPO}  ->  ${LOCAL_REPO}"

# --files-from reads the list locally and skips any entry missing on the remote.
# rsync returns 23/24 for "some files vanished/were skipped" — those are OK here.
rc=0
printf '%s\n' "${PATHS[@]}" \
  | rsync -avz --files-from=- \
      "${PI_SSH}:${PI_REPO}/" \
      "${LOCAL_REPO}/" || rc=$?
if [ "$rc" != 0 ] && [ "$rc" != 23 ] && [ "$rc" != 24 ]; then
  echo "rsync failed (exit $rc)" >&2
  exit "$rc"
fi

echo
echo ">> git status in ${LOCAL_REPO}:"
git -C "${LOCAL_REPO}" status --short

echo
echo ">> Review with:  git -C '${LOCAL_REPO}' diff"
echo ">> Then commit:  git -C '${LOCAL_REPO}' add -A && git -C '${LOCAL_REPO}' commit"

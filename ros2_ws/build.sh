#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /opt/ros/jazzy/setup.bash

cd "$SCRIPT_DIR" || exit
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DPython3_EXECUTABLE=/usr/bin/python3 -DCMAKE_CXX_FLAGS="-g0" --packages-skip vision_msgs_rviz_plugins
source "$SCRIPT_DIR/install/local_setup.bash"

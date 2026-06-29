#!/bin/bash
# Launch the pupper neural_controller (RL walking policy) under the RoboStack
# pixi env. Post-Trixie migration: ROS 2 lives in the pixi env, not /opt/ros/jazzy.

WS="/home/pi/pupperv3/ros2_ws"
export PATH="/home/pi/.pixi/bin:$PATH"

# Activate the RoboStack Jazzy environment (provides ROS 2 — replaces /opt/ros/jazzy).
eval "$(pixi shell-hook -e jazzy --manifest-path "$WS/pixi.toml")"

# Overlay the built workspace (neural_controller, control_board_hardware_interface, ...).
source "$WS/install/local_setup.bash"

ROS_LOCALHOST_ONLY=1 ros2 launch neural_controller launch.py

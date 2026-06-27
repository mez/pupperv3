# Pupper V3

Quadruped robot with ROS2 locomotion control, Hailo AI HAT vision, and an optional AI voice assistant.

## Getting started on real hardware

### 1. Flash the base image

Build or download the base image and flash it to a USB drive or SD card:

```bash
cd infra/pupper_image_builder
bash make_image.sh
# then flash: sudo dd if=pupOS_pios_base_*.img of=/dev/rdiskN bs=4m status=progress
```

See [infra/pupper_image_builder/README.md](infra/pupper_image_builder/README.md) for full details and options.

### 2. Configure WiFi

```bash
ssh pi@pupper.local         # password: pupper123
sudo bash setup_wifi.sh "YourSSID" "YourPassword"
sudo reboot
```

### 3. Install ROS2 and build the workspace

```bash
ssh pi@pupper.local
sudo bash install_ros.sh    # ~30-60 min
```

### 4. (Optional) Install the AI stack

```bash
sudo bash install_ai.sh     # Rust, pupper-rs GUI, LiveKit voice agent
```

Then create `/home/pi/pupperv3-monorepo/ai/llm-ui/agent-starter-python/.env` with your API keys and restart the service:
```bash
sudo systemctl restart agent-starter-python
```

---

## Simulation on a dev machine (x86 Ubuntu 24)

```bash
sudo apt install git-lfs
git lfs install
git clone https://github.com/mez/pupperv3.git --recurse-submodules
./install_dev_dependencies.sh
cd ros2_ws && source build.sh
```

---

## Docs

See the [documentation](https://pupper-v3-documentation.readthedocs.io/en/latest/).

## Notes

- Camera FPS is 10hz by default — adjustable in `ros2_ws/src/neural_controller/launch/config.yaml` via `FrameDurationLimits: [100000, 100000]`

## Adding animations

1. Hold L1 until BAG status icon turns green (recording starts)
2. Move Pupper through the desired motion
3. Press R1 to stop recording
4. View the mcap file in Foxglove to verify
5. Run `scripts/mcap_to_csv.py [path_to_mcap] -s START_TIME -e END_TIME` to convert
6. Copy csv to `ros2_ws/src/animation_controller_py/launch/animations`
7. Rebuild: `./build.sh`
8. Update `pupster.py` with the animation nickname

## Camera
Launch mock camera and detection nodes so you can experiment with vision with simulated robot
```sh
ros2 launch hailo detection_with_mock_camera_launch.py
```

Launch Foxglove bridge so you can see detections in Foxglove studio
```sh
ros2 run foxglove_bridge foxglove_bridge
```
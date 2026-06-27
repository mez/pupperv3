#!/bin/bash -e
# install_ai.sh — Run on the Pi after install_ros.sh to add the AI stack.
# Installs: Rust, pupper-rs GUI, LiveKit voice agent
# Usage: sudo bash install_ai.sh
#
# Before the agent will work, create an .env file at:
#   /home/pi/pupperv3-monorepo/ai/llm-ui/agent-starter-python/.env
# with the following keys:
#   LIVEKIT_URL=
#   LIVEKIT_API_KEY=
#   LIVEKIT_API_SECRET=
#   OPENAI_API_KEY=
#   DEEPGRAM_API_KEY=
#   CARTESIA_API_KEY=

set -x

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash install_ai.sh"
    exit 1
fi

DEFAULT_USER=${SUDO_USER:-pi}
HOME_DIR=/home/$DEFAULT_USER

export DEBIAN_FRONTEND=noninteractive

################################ Install Rust ################################
export CARGO_HOME="$HOME_DIR/.cargo"
export RUSTUP_HOME="$HOME_DIR/.rustup"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME_DIR/.cargo/env"
rustup target add aarch64-unknown-linux-gnu

echo "export CARGO_HOME=$HOME_DIR/.cargo" >> "$HOME_DIR/.bashrc"
echo "export RUSTUP_HOME=$HOME_DIR/.rustup" >> "$HOME_DIR/.bashrc"
echo "source $HOME_DIR/.cargo/env" >> "$HOME_DIR/.bashrc"

################################ LiveKit agent deps ################################
# Note: livekit>=1.0.14 requires glibc>=2.38 which PiOS Bookworm does not have
sudo rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
pip install "livekit==1.0.13" "livekit-agents[cartesia,google,openai,deepgram,silero,turn-detector]==1.2.15"
pip install python-dotenv pandas

pip install "numpy<2" "opencv-python" "pyzmq"

################################ Build pupper-rs GUI ################################
cd "$HOME_DIR/pupperv3-monorepo/pupper-rs"
cargo build --release --target aarch64-unknown-linux-gnu

################################ Install systemd services ################################
bash "$HOME_DIR/pupperv3-monorepo/pupper-rs/install_service.sh"
bash "$HOME_DIR/pupperv3-monorepo/ai/llm-ui/agent-starter-python/install_service.sh"
systemctl enable systemd-time-wait-sync.service

chown -R "$DEFAULT_USER:$DEFAULT_USER" "$HOME_DIR"

echo ""
echo "AI stack installed successfully."
echo "Create your .env file at:"
echo "  $HOME_DIR/pupperv3-monorepo/ai/llm-ui/agent-starter-python/.env"
echo "Then: sudo systemctl restart agent-starter-python"

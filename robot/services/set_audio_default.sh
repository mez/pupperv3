#!/bin/bash
# set_audio_default.sh — Make the HifiBerry DAC the default audio sink and max
# its volume. Driven by volume-max.service on boot.
#
# Why not `amixer sset Master 100%`? The Pi's audio stack is PipeWire/WirePlumber
# and the HifiBerry pcm5102a is a fixed-output DAC with NO ALSA 'Master' control,
# so the old amixer call silently failed. We use wpctl instead, and target the
# HifiBerry by its STABLE node name (numeric wpctl ids change across boots).
#
# NOTE: the HifiBerry is line-level — you still need a powered/amplified speaker
# on its output for sound to be audible.
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
TARGET="alsa_output.platform-soc_107c000000_sound.stereo-fallback"

# Wait for the user's PipeWire session to come up (service may start first).
for _ in $(seq 1 30); do
    wpctl status >/dev/null 2>&1 && break
    sleep 1
done

# Resolve the WirePlumber node id for the HifiBerry sink by its stable node.name.
id=""
for n in $(wpctl status 2>/dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -oE '[0-9]+\.' | tr -d '.'); do
    if wpctl inspect "$n" 2>/dev/null | grep -q "node.name = \"$TARGET\""; then
        id="$n"
        break
    fi
done

if [ -z "$id" ]; then
    echo "set_audio_default: HifiBerry sink ($TARGET) not found" >&2
    exit 1
fi

wpctl set-default "$id"
wpctl set-volume "$id" 1.0
echo "set_audio_default: default sink -> $id ($TARGET), volume 100%"

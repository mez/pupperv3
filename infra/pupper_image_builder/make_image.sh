#!/bin/bash -e

set -x
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${SCRIPT_DIR}/base_image"

GIT_COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Trixie images have the orphan_file ext4 feature which causes resize2fs to fail
# inside packer-builder-arm (uses resize2fs 1.46, predating orphan_file support).
# We download to a fixed local path, verify SHA256, strip orphan_file, and point
# packer at the local file directly — no cache hash prediction needed.
IMAGE_URL="https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-06-19/2026-06-18-raspios-trixie-arm64.img.xz"
SHA256_URL="https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-06-19/2026-06-18-raspios-trixie-arm64.img.xz.sha256"
BASE_IMG="trixie_base.img.xz"

if [ ! -f "${BASE_IMG}.stripped" ]; then
    if [ ! -f "${BASE_IMG}" ]; then
        echo "Downloading Trixie base image..."
        curl -L --progress-bar -o "${BASE_IMG}" "${IMAGE_URL}"

        echo "Verifying download integrity..."
        EXPECTED_HASH=$(curl -sSL "${SHA256_URL}" | awk '{print $1}')
        ACTUAL_HASH=$(shasum -a 256 "${BASE_IMG}" | awk '{print $1}')
        if [ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]; then
            echo "ERROR: SHA256 mismatch! Expected ${EXPECTED_HASH}, got ${ACTUAL_HASH}" >&2
            rm -f "${BASE_IMG}"
            exit 1
        fi
        echo "Checksum verified."
    fi

    # If stripping fails, remove the marker so the next run retries cleanly
    trap 'rm -f "${BASE_IMG}.stripped"' ERR

    echo "Stripping orphan_file ext4 feature from root partition..."
    docker run --rm --privileged \
        -v "${PWD}:/work" \
        ubuntu:24.04 bash -c "
            set -e
            apt-get update -qq
            apt-get install -y e2fsprogs xz-utils -qq
            cd /work
            xz -dk '${BASE_IMG}' -c > raw.img
            # Root partition on Trixie (2026-06-18) starts at sector 1064960
            OFFSET_BYTES=$(( 1064960 * 512 ))
            LOOP=\$(losetup --find --show -o \$OFFSET_BYTES raw.img)
            e2fsck -fy \$LOOP || true
            tune2fs -O ^orphan_file \$LOOP
            losetup -d \$LOOP
            xz -z -T0 raw.img -c > '${BASE_IMG}.new'
            mv '${BASE_IMG}.new' '${BASE_IMG}'
            rm raw.img
        "
    touch "${BASE_IMG}.stripped"
    trap - ERR
    echo "Pre-processing complete."
fi

docker pull mkaczanowski/packer-builder-arm:latest

echo "Creating pupperv3 repo tarball for baking into image..."
tar -czf resources/pupperv3_src.tar.gz \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -C "${REPO_ROOT}" \
    ros2_ws ai robot pupper-rs scripts README.md \
    -C "${REPO_ROOT}/infra/pupper_image_builder" \
    install_scripts

docker run --rm --privileged -v /dev:/dev -v "${PWD}:/build" mkaczanowski/packer-builder-arm:latest init pios_base_arm64.pkr.hcl
docker run --rm --privileged -v /dev:/dev -v "${PWD}:/build" mkaczanowski/packer-builder-arm:latest build pios_base_arm64.pkr.hcl

echo "Cleaning up staged tarball..."
rm -f resources/pupperv3_src.tar.gz

if [ -f "pupOS_pios_base.img" ]; then
  mv -f "pupOS_pios_base.img" "pupOS_pios_base_${GIT_COMMIT_SHORT}.img"
  echo "Image saved as pupOS_pios_base_${GIT_COMMIT_SHORT}.img"
fi

# Write cloud-init user-data to the FAT boot partition
# (packer's chroot can't reach the FAT partition, so we do it post-build on the host)
IMG="pupOS_pios_base_${GIT_COMMIT_SHORT}.img"
echo "Writing cloud-init user-data to boot partition..."
hdiutil attach "${IMG}" -nobrowse
cp resources/user-data /Volumes/bootfs/user-data
hdiutil detach /Volumes/bootfs
echo "user-data written successfully."

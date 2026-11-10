#!/usr/bin/env bash
set -euo pipefail

# Rebuild the SIGFM-enabled libfprint for ELAN7001 / 04f3:3128.
# Usage: ./build.sh [source-dir]
# Default source dir: ~/src/libfprint-rsd

SRC="${1:-$HOME/src/libfprint-rsd}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH="$HERE/elanspi-3128-sigfm.patch"
PREFIX="/opt/elan3128"
REPO="https://github.com/rsd/libfprint.git"
BRANCH="sigfm-0078"

if ! command -v meson >/dev/null || ! command -v ninja >/dev/null; then
  echo "meson and ninja are required." >&2
  if command -v pacman >/dev/null; then
    echo "Install them with: sudo pacman -S --needed meson ninja doctest opencv" >&2
  elif command -v apt >/dev/null; then
    echo "Install them with: sudo apt install meson ninja-build libopencv-dev libdoctest-dev" >&2
  elif command -v dnf >/dev/null; then
    echo "Install them with: sudo dnf install meson ninja-build opencv-devel doctest-devel" >&2
  else
    echo "Install meson, ninja, OpenCV, and doctest development packages for your distribution." >&2
  fi
  exit 1
fi

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$SRC"
fi

cd "$SRC"

# The rsd fork already contains the 04f3:3128 entry with ELANSPI_90LEFT_ROTATE.
if ! grep -q '0x3128' libfprint/drivers/elanspi.h; then
  echo "error: this source tree has no 0x3128 entry; check libfprint/drivers/elanspi.h" >&2
  exit 1
fi

if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH"
else
  echo "Patch is already applied or the source version differs; continuing." >&2
fi

rm -rf build
meson setup build \
  --prefix="$PREFIX" \
  -Ddrivers=elanspi \
  -Dudev_rules=disabled \
  -Ddoc=false \
  -Dintrospection=false \
  -Dinstalled-tests=false

ninja -C build
sudo ninja -C build install
sudo systemctl restart fprintd

echo
echo "Done. Verify with:"
echo "  cat /sys/module/spidev/parameters/bufsiz   # 32768"
echo "  fprintd-list \"\$USER\""

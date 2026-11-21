#!/usr/bin/env bash
# Shared helpers for the NanoPi M1 image build.

set -euo pipefail

PROJECT_DIR=${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CACHE=${CACHE:-$PROJECT_DIR/../.cache}
OUT=${OUT:-$PROJECT_DIR/out}

KERNEL_PROJECT=${KERNEL_PROJECT:-$PROJECT_DIR/../nanopi-m1-kernel}
KERNEL_OUT=${KERNEL_OUT:-$KERNEL_PROJECT/out}

WORK=$CACHE/work-image
ROOTFS=$WORK/rootfs

UBOOT_VERSION=${UBOOT_VERSION:-2026.07}
SUITE=${SUITE:-trixie}
MIRROR=${MIRROR:-http://mirrors.aliyun.com/debian}
IMG_SIZE=${IMG_SIZE:-2G}
ROOT_PASSWORD=${ROOT_PASSWORD:-nanopi}
JOBS=${JOBS:-$(nproc)}

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m***\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$CACHE/dl" "$CACHE/build" "$OUT" "$WORK"

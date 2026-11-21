#!/usr/bin/env bash
# Shared helpers for the NanoPi M1 kernel build.
# Sourced by the other scripts; not meant to be executed directly.

set -euo pipefail

PROJECT_DIR=${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CACHE=${CACHE:-$PROJECT_DIR/.cache}
OUT=${OUT:-$PROJECT_DIR/out}
JOBS=${JOBS:-$(nproc)}
KERNEL_VERSION=${KERNEL_VERSION:-6.18.64}
KERNEL_MIRROR=${KERNEL_MIRROR:-https://cdn.kernel.org/pub/linux/kernel/v6.x}

SRC=$CACHE/build/linux-$KERNEL_VERSION
TARBALL=$CACHE/dl/linux-$KERNEL_VERSION.tar.xz
TOOLCHAIN_ENV=$CACHE/toolchain.env

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m***\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$CACHE/dl" "$CACHE/build" "$OUT"

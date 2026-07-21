#!/bin/sh
# make-iso.sh — produce a bootable SunshineBSD ISO by remastering the
# pinned upstream FreeBSD release ISO (Stage 0).
#
# One job: orchestration. Each build stage is its own single-job
# component under tools/iso/, run in dependency order with its inputs
# passed explicitly as SUNISO_* environment variables:
#
#   tools/iso/fetch-base.sh       download + verify + extract upstream ISO
#   tools/iso/brand-tree.sh       SunshineBSD identity on the live tree
#   tools/iso/stage-tooling.sh    native tooling, config, docs, /service
#   tools/iso/stage-packages.sh   desktop packages (fetch-pkg) + Xorg conf
#   tools/iso/stage-boot-chain.sh rc.d boot chain + rc.conf.d drop-ins
#   tools/fetch-fonts.sh          system fonts (predates the split)
#   tools/iso/pack-dist.sh        live-tree mirror + sunshine.txz + MANIFEST
#   tools/iso/build-iso.sh        xorriso BIOS+UEFI rebuild into dist/
#
# The payload stages build everything SunshineBSD adds into one staging
# tree ($SUNISO_STAGE), which pack-dist.sh then fans out two ways — the
# live tree for VM boot-testing and sunshine.txz for a real bsdinstall —
# so both paths come from a single source instead of duplicated install
# logic that could drift apart.
#
# This is the Stage 0 test path: it produces something bootable in QEMU
# today. The real from-source ISO comes from `make world` + `make image`
# once a FreeBSD build host is available.
#
# Runs on Linux (incl. WSL) or FreeBSD. Needs: curl, bsdtar, xorriso,
# sha256sum (or sha256).
#
# usage: tools/make-iso.sh
#
# Environment:
#   FREEBSD_ISO_VERSION    upstream release to remaster (default: 14.4-RELEASE)
#   FREEBSD_ISO_ARCH       architecture (default: amd64)
#   FREEBSD_ISO_FLAVOR     disc1 | bootonly | dvd1 (default: disc1)
#   FREEBSD_ISO_MIRROR     base URL (default: https://download.freebsd.org)
#   SUNSHINE_ISO_WORK      scratch dir (default: ~/.cache/sunshinebsd/iso-build)
#   SUNSHINE_TXZ_COMPRESSION  xz | zstd | gzip (default: xz) -- sunshine.txz's
#                          codec. xz is smallest but slow on a tree this size
#                          (Xfce + Qt6/KDE bits); `make iso-dev` sets zstd for
#                          fast local rebuild/boot-test iteration. Release
#                          builds (`make iso`) stay xz for the smallest
#                          download. The file is still named sunshine.txz
#                          either way -- bsdtar auto-detects the real codec
#                          from content on extract, same as bsdinstall does.

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root_dir/tools/iso/lib.sh"

# --- inputs, validated before any real work ------------------------------

# 14.4-RELEASE (bumped from 14.3, 2026-07-21): the FreeBSD:14 pkg repo
# builds its kernel modules -- drm-61-kmod/i915kms in particular --
# against __FreeBSD_version 1404000 (14.4), so the remastered kernel
# must be 14.4 for the DRM kmod to load. Verified live 2026-07-21 that
# FreeBSD-14.4-RELEASE-amd64-disc1.iso + its CHECKSUM.SHA256 exist on
# download.freebsd.org before bumping.
SUNISO_VERSION="${FREEBSD_ISO_VERSION:-14.4-RELEASE}"
SUNISO_ARCH="${FREEBSD_ISO_ARCH:-amd64}"
SUNISO_FLAVOR="${FREEBSD_ISO_FLAVOR:-disc1}"
SUNISO_MIRROR="${FREEBSD_ISO_MIRROR:-https://download.freebsd.org}"
SUNISO_LUA="${LUA:-lua}"
SUNISO_TXZ="${SUNSHINE_TXZ_COMPRESSION:-xz}"

# Fail fast on a bad codec now, not after the multi-minute package fetch
# (pack-dist.sh re-derives the flag from the same single definition).
txz_flag_for "$SUNISO_TXZ" >/dev/null || exit 2

SUNISO_ROOT="$root_dir"
SUNISO_WORK="${SUNSHINE_ISO_WORK:-$HOME/.cache/sunshinebsd/iso-build}"
SUNISO_CACHE="$HOME/.cache/sunshinebsd/downloads"
SUNISO_TREE="$SUNISO_WORK/tree"
SUNISO_STAGE="$SUNISO_WORK/sunshine-dist"
SUNISO_DIST="$root_dir/dist"
SUNISO_NUMVER="${SUNISO_VERSION%%-*}"

for tool in curl bsdtar xorriso "$SUNISO_LUA"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "make-iso: missing tool: $tool" >&2
        echo "make-iso: on Fedora: dnf install curl bsdtar xorriso lua" >&2
        exit 1
    }
done
init_sha256

export SUNISO_ROOT SUNISO_WORK SUNISO_CACHE SUNISO_TREE SUNISO_STAGE \
    SUNISO_DIST SUNISO_VERSION SUNISO_ARCH SUNISO_FLAVOR SUNISO_MIRROR \
    SUNISO_NUMVER SUNISO_LUA SUNISO_TXZ

# --- run the stages in dependency order ----------------------------------

sh "$root_dir/tools/iso/fetch-base.sh"
sh "$root_dir/tools/iso/brand-tree.sh"

# The payload staging tree is created fresh here (fetch-base.sh wiped
# $SUNISO_WORK) so every stage-*.sh can assume it exists and is empty.
rm -rf "$SUNISO_STAGE"
mkdir -p "$SUNISO_STAGE"

sh "$root_dir/tools/iso/stage-tooling.sh"
sh "$root_dir/tools/iso/stage-packages.sh"
sh "$root_dir/tools/iso/stage-boot-chain.sh"

# Open Sans (PLAN.md's `Font: Open Sans` foundation decision) and Noto
# Color Emoji (emoji fallback), fetched live from Google Fonts.
log "installing fonts (Open Sans, Noto Color Emoji)"
sh "$root_dir/tools/fetch-fonts.sh" "$SUNISO_STAGE"

sh "$root_dir/tools/iso/pack-dist.sh"
sh "$root_dir/tools/iso/build-iso.sh"

#!/bin/sh
# fetch-freebsd.sh — fetch the upstream FreeBSD source tree (Stage 0).
#
# One job: place a pinned FreeBSD source checkout in vendor/freebsd-src.
# The tree is never committed to the SunshineBSD repository; SunshineBSD
# components are overlaid onto it at build time.
#
# Usage:
#   tools/fetch-freebsd.sh [branch-or-tag]
#
# Environment:
#   FREEBSD_REPO    upstream git URL (default: official FreeBSD mirror)
#   FREEBSD_REF     branch or tag to pin (default: releng/14.2)

set -eu

FREEBSD_REPO="${FREEBSD_REPO:-https://git.freebsd.org/src.git}"
FREEBSD_REF="${1:-${FREEBSD_REF:-releng/14.2}}"

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dest="$root_dir/vendor/freebsd-src"

if [ -e "$dest/.git" ]; then
    echo "fetch-freebsd: existing checkout found, updating to $FREEBSD_REF"
    git -C "$dest" fetch --depth 1 origin "$FREEBSD_REF"
    git -C "$dest" checkout --detach FETCH_HEAD
else
    echo "fetch-freebsd: cloning $FREEBSD_REPO ($FREEBSD_REF)"
    mkdir -p "$root_dir/vendor"
    git clone --depth 1 --branch "$FREEBSD_REF" "$FREEBSD_REPO" "$dest"
fi

echo "fetch-freebsd: done."
git -C "$dest" log -1 --format='fetch-freebsd: pinned at %h (%s)'

#!/bin/sh
# make-image.sh — produce a bootable SunshineBSD VM image (Stage 0).
#
# One job: run the upstream release vm-image machinery against the built
# world/kernel and drop the result in dist/. Requires a FreeBSD host,
# root privileges (the release framework mounts filesystems), and a
# completed `make world kernel`.
#
# usage: tools/make-image.sh
#
# Environment:
#   KERNCONF   kernel configuration (default: SUNSHINE)
#   VMFORMAT   image format for qemu (default: qcow2)

set -eu

if [ "$(uname -s)" != "FreeBSD" ]; then
    echo "make-image: images must be built on a FreeBSD host (host is $(uname -s))" >&2
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "make-image: the FreeBSD release framework needs root" >&2
    exit 1
fi

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$root_dir/vendor/freebsd-src"
[ -d "$src" ] || { echo "make-image: run 'make fetch' and 'make world kernel' first" >&2; exit 1; }

KERNCONF="${KERNCONF:-SUNSHINE}"
VMFORMAT="${VMFORMAT:-qcow2}"
export MAKEOBJDIRPREFIX="$root_dir/obj"

cd "$src/release"
make vm-image WITH_VMIMAGES=yes VMFORMATS="$VMFORMAT" KERNCONF="$KERNCONF"

mkdir -p "$root_dir/dist"
found=""
for img in "$MAKEOBJDIRPREFIX"/*"/release/vm."*"$VMFORMAT"* \
           "$MAKEOBJDIRPREFIX"/*"/src/release/vm."*"$VMFORMAT"*; do
    if [ -f "$img" ]; then
        cp "$img" "$root_dir/dist/sunshinebsd.$VMFORMAT"
        found="yes"
        break
    fi
done
if [ -z "$found" ]; then
    echo "make-image: vm-image finished but no vm.$VMFORMAT found under $MAKEOBJDIRPREFIX" >&2
    exit 1
fi

echo "make-image: wrote dist/sunshinebsd.$VMFORMAT"

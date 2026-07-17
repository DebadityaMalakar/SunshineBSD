#!/bin/sh
# build-os.sh — build SunshineBSD world and/or kernel (Stage 0).
#
# One job: brand the vendored FreeBSD tree and run the upstream build.
# Supported build hosts:
#   FreeBSD  native build with make(1)
#   Linux    (incl. WSL/Fedora) via FreeBSD's official cross-build
#            bootstrap, tools/build/make.py (needs clang, lld, python3,
#            libarchive-devel, bmake bootstraps itself)
#
# usage: tools/build-os.sh {world|kernel|all}
#
# Environment:
#   KERNCONF   kernel configuration (default: SUNSHINE)
#   BUILDJOBS  parallel jobs (default: number of CPUs)
#   TARGET / TARGET_ARCH   cross target (default: amd64/amd64 on Linux)

set -eu

[ $# -eq 1 ] || { echo "usage: tools/build-os.sh {world|kernel|all}" >&2; exit 2; }
target="$1"
case "$target" in
    world|kernel|all) ;;
    *) echo "build-os: unknown target '$target'" >&2; exit 2 ;;
esac

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$root_dir/vendor/freebsd-src"
if [ ! -d "$src" ]; then
    echo "build-os: $src not found; run 'make fetch' first" >&2
    exit 1
fi

host=$(uname -s)
KERNCONF="${KERNCONF:-SUNSHINE}"
TARGET="${TARGET:-amd64}"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
case "$host" in
    FreeBSD)
        BUILDJOBS="${BUILDJOBS:-$(sysctl -n hw.ncpu)}"
        run_make() {
            (cd "$src" && make -j"$BUILDJOBS" "$@")
        }
        ;;
    Linux)
        BUILDJOBS="${BUILDJOBS:-$(nproc)}"
        if ! command -v python3 >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
            echo "build-os: Linux host build needs python3 and clang" >&2
            echo "build-os: on Fedora: dnf install clang lld python3 libarchive-devel bzip2-devel zlib-devel" >&2
            exit 1
        fi
        run_make() {
            (cd "$src" && python3 tools/build/make.py -j"$BUILDJOBS" \
                TARGET="$TARGET" TARGET_ARCH="$TARGET_ARCH" "$@")
        }
        ;;
    *)
        echo "build-os: unsupported build host $host (use FreeBSD, or Linux/WSL)" >&2
        exit 1
        ;;
esac

export MAKEOBJDIRPREFIX="$root_dir/obj"
mkdir -p "$MAKEOBJDIRPREFIX"

"$root_dir/tools/brand-freebsd.sh"

case "$target" in
    world)
        run_make buildworld
        ;;
    kernel)
        run_make buildkernel KERNCONF="$KERNCONF"
        ;;
    all)
        run_make buildworld
        run_make buildkernel KERNCONF="$KERNCONF"
        ;;
esac

echo "build-os: $target complete (host=$host KERNCONF=$KERNCONF)"

#!/bin/sh
# fetch-pkg.sh — install FreeBSD packages, plus their full transitive
# dependency closure, into a target root directory.
#
# One job: resolve + fetch + extract binary packages straight from the
# live FreeBSD pkg repo (src/pkgfetch does the resolving). This is a
# plain archive extraction, not a real `pkg` database registration: no
# +MANIFEST/+COMPACT_MANIFEST bookkeeping is kept in the target, no
# pkg-install scripts run (this build host is not necessarily FreeBSD,
# so a fetched package's own scripts can't safely execute here anyway),
# and package signatures are not verified -- this is a build-time
# convenience, not a substitute for pkg(8)'s trust model on the
# installed system.
#
# Runs on Linux (incl. WSL) or FreeBSD. Needs: curl, bsdtar, lua.
#
# usage: tools/fetch-pkg.sh <rootdir> <package>...
#
# Environment:
#   PKG_ABI             FreeBSD:<release>:<arch> (default: FreeBSD:14:amd64)
#   PKG_MIRROR          base URL (default: https://pkg.freebsd.org)
#   LUA                 lua interpreter (default: lua)
#   SUNSHINE_PKG_CACHE  download cache (default: ~/.cache/sunshinebsd/pkg)

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LUA="${LUA:-lua}"
ABI="${PKG_ABI:-FreeBSD:14:amd64}"
MIRROR="${PKG_MIRROR:-https://pkg.freebsd.org}"
cache="${SUNSHINE_PKG_CACHE:-$HOME/.cache/sunshinebsd/pkg}"

if [ "$#" -lt 2 ]; then
    echo "usage: fetch-pkg.sh <rootdir> <package>..." >&2
    exit 2
fi
tree="$1"
shift

for tool in curl bsdtar cut "$LUA"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "fetch-pkg: missing tool: $tool" >&2
        exit 1
    }
done

mkdir -p "$cache" "$tree"

# --- 1. package index --------------------------------------------------

site="$cache/packagesite-$(echo "$ABI" | tr ':' '_').yaml"
if [ ! -f "$site" ]; then
    echo "fetch-pkg: downloading package index for $ABI"
    curl -fL --proto '=https' -o "$cache/packagesite.pkg.$$" "$MIRROR/$ABI/latest/packagesite.pkg"
    bsdtar -xOf "$cache/packagesite.pkg.$$" packagesite.yaml > "$site.$$"
    rm -f "$cache/packagesite.pkg.$$"
    mv "$site.$$" "$site"
fi

# --- 2. resolve the transitive closure ----------------------------------

resolved=$("$LUA" "$root_dir/src/pkgfetch/pkgfetch" resolve "$site" "$@")

# --- 3. fetch + extract each package ------------------------------------

echo "$resolved" | while IFS="$(printf '\t')" read -r name repopath version; do
    [ -n "$name" ] || continue
    pkgfile="$cache/$(basename "$repopath")"
    if [ ! -f "$pkgfile" ]; then
        curl -fL --proto '=https' -o "$pkgfile.$$" "$MIRROR/$ABI/latest/$repopath"
        mv "$pkgfile.$$" "$pkgfile"
    fi
    echo "fetch-pkg: installing $name-$version"
    bsdtar -xf "$pkgfile" -C "$tree" --exclude '+*'
done

# --- 4. record what was installed ---------------------------------------
# This is a fetch+extract install, not a real `pkg` database registration
# (see the header comment), so `pkg info` on the booted system will not
# show any of this -- it has no other way to know. This manifest is that
# other way: a plain, human-readable record of exactly what fetch-pkg.sh
# put on the system and at what version, independent of pkg(8) entirely.

manifest_dir="$tree/usr/local/share/sunshine"
mkdir -p "$manifest_dir"
{
    echo "# Packages installed by fetch-pkg.sh (fetch+extract, not registered with pkg(8))."
    echo "# pkg info/pkg query will NOT show these -- this file is the only record."
    echo "# name<TAB>version"
    echo "$resolved" | cut -f 1,3
} > "$manifest_dir/pkg-manifest.txt.$$"
mv "$manifest_dir/pkg-manifest.txt.$$" "$manifest_dir/pkg-manifest.txt"

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
#   FETCH_PKG_JOBS      how many packages to fetch+extract at once (default: 4)

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LUA="${LUA:-lua}"
ABI="${PKG_ABI:-FreeBSD:14:amd64}"
MIRROR="${PKG_MIRROR:-https://pkg.freebsd.org}"
cache="${SUNSHINE_PKG_CACHE:-$HOME/.cache/sunshinebsd/pkg}"
jobs="${FETCH_PKG_JOBS:-4}"

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

case "$jobs" in
    *[!0-9]*|"")
        echo "fetch-pkg: FETCH_PKG_JOBS must be a positive integer, got '$jobs'" >&2
        exit 2
        ;;
esac
if [ "$jobs" -lt 1 ]; then
    echo "fetch-pkg: FETCH_PKG_JOBS must be at least 1, got '$jobs'" >&2
    exit 2
fi

mkdir -p "$cache" "$tree"

# --- 1. package index --------------------------------------------------

site="$cache/packagesite-$(echo "$ABI" | tr ':' '_').yaml"
if [ ! -f "$site" ]; then
    echo "fetch-pkg: downloading package index for $ABI"
    curl -fL --proto '=https' --connect-timeout 15 --retry 2         --retry-delay 3 --retry-max-time 120         -o "$cache/packagesite.pkg.$$" "$MIRROR/$ABI/latest/packagesite.pkg"
    bsdtar -xOf "$cache/packagesite.pkg.$$" packagesite.yaml > "$site.$$"
    rm -f "$cache/packagesite.pkg.$$"
    mv "$site.$$" "$site"
fi

# --- 2. resolve the transitive closure ----------------------------------

resolved=$("$LUA" "$root_dir/src/pkgfetch/pkgfetch" resolve "$site" "$@")

# --- 3. fetch + extract each package ------------------------------------
# Up to $jobs packages at once (default 4). Each runs in its own
# background subshell; a bounded batch is launched, then waited on before
# the next batch starts, so this stays plain, portable POSIX sh (no
# `wait -n`, which is a bash-ism this project's #!/bin/sh scripts avoid).
# A background job's own failure does NOT trip `set -e` in the parent, so
# each job records its own failure into $fail_dir instead of relying on
# that -- silently losing one failed package in a batch of otherwise-fine
# ones is exactly the kind of thing DOCS/ENGINEERING.MD's "no silent
# failure" rule exists to prevent.

fail_dir="$cache/.fetch-pkg-fail.$$"
mkdir -p "$fail_dir"

fetch_one() { # name repopath version
    name="$1"; repopath="$2"; version="$3"
    pkgfile="$cache/$(basename "$repopath")"
    if [ ! -f "$pkgfile" ]; then
        if ! curl -fL --proto '=https' --connect-timeout 15 --retry 2             --retry-delay 3 --retry-max-time 120             -o "$pkgfile.$$.$name" "$MIRROR/$ABI/latest/$repopath"; then
            echo "fetch-pkg: download failed: $name" >"$fail_dir/$name"
            return 1
        fi
        mv "$pkgfile.$$.$name" "$pkgfile"
    fi
    echo "fetch-pkg: installing $name-$version"
    if ! bsdtar -xf "$pkgfile" -C "$tree" --exclude '+*'; then
        echo "fetch-pkg: extract failed: $name" >"$fail_dir/$name"
        return 1
    fi
}

# Read from a file, not `echo | while`: a piped while-loop runs in a
# subshell, and background jobs started inside it are ORPHANED when the
# subshell exits -- the final partial batch (up to jobs-1 packages) was
# still downloading/extracting while the caller moved on to pack the
# tree, and the parent's `wait` below cannot see another shell's
# children. Found 2026-07-19 while auditing this stage; the loop must
# run in this shell for `wait` to actually cover every job.
resolved_list="$cache/.fetch-pkg-resolved.$$"
printf '%s\n' "$resolved" > "$resolved_list"
n=0
while IFS="$(printf '\t')" read -r name repopath version; do
    [ -n "$name" ] || continue
    fetch_one "$name" "$repopath" "$version" &
    n=$((n + 1))
    if [ "$n" -ge "$jobs" ]; then
        wait
        n=0
    fi
done < "$resolved_list"
wait
rm -f "$resolved_list"

if [ -n "$(ls -A "$fail_dir" 2>/dev/null)" ]; then
    echo "fetch-pkg: one or more packages failed:" >&2
    cat "$fail_dir"/* >&2
    rm -rf "$fail_dir"
    exit 1
fi
rm -rf "$fail_dir"

# --- 4. install sample configs the bypassed pkg-install scripts would have
# One real, verified case each (2026-07-18, live FreeBSD:14:amd64 packages):
# dbus ships etc/dbus-1/{system,session}.conf.sample and sddm ships
# etc/sddm.conf.default plus three etc/pam.d/*.default files, each installed
# by a `lua_scripts.post-install` entry that does exactly this: copy the
# sample to its suffix-stripped name if (and only if) that name doesn't
# already exist. fetch-pkg.sh's plain bsdtar extraction skips all pkg
# scripts (see the header comment), so this step re-does that one
# file-copy effect generically for every package fetched, not just the two
# confirmed above -- any future package with the same *.sample/*.default
# convention is covered automatically.

find "$tree" \( -name '*.sample' -o -name '*.default' \) -type f | \
    while IFS= read -r sample; do
        target="${sample%.sample}"
        target="${target%.default}"
        [ -f "$target" ] || cp "$sample" "$target"
    done

# --- 5. record what was installed ---------------------------------------
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

#!/bin/sh
# brand-freebsd.sh — mark the vendored FreeBSD tree as a SunshineBSD fork.
#
# One job: apply SunshineBSD identity to the upstream source tree.
#   1. Copy the overlay/ tree (additive files, e.g. the SUNSHINE kernconf).
#   2. Rebrand sys/conf/newvers.sh: TYPE becomes "SunshineBSD" (this is
#      what uname -s and the boot banner report) and BRANCH is prefixed
#      with SUNSHINE.
#   3. Install branding/motd as the login message template.
#
# Idempotent: safe to run repeatedly. Every change is verified after it
# is made (DOCS/ENGINEERING.MD 3.6).
#
# usage: tools/brand-freebsd.sh

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$root_dir/vendor/freebsd-src"
if [ ! -d "$src" ]; then
    echo "brand-freebsd: $src not found; run 'make fetch' first" >&2
    exit 1
fi

newvers="$src/sys/conf/newvers.sh"
if [ ! -f "$newvers" ]; then
    echo "brand-freebsd: $newvers not found; tree layout unexpected" >&2
    exit 1
fi

echo "brand-freebsd: copying overlay/"
cp -R "$root_dir/overlay/." "$src/"
if [ ! -f "$src/sys/amd64/conf/SUNSHINE" ]; then
    echo "brand-freebsd: overlay copy failed (SUNSHINE kernconf missing)" >&2
    exit 1
fi

if grep -q '^TYPE="SunshineBSD"' "$newvers"; then
    echo "brand-freebsd: newvers.sh already branded"
else
    echo "brand-freebsd: rebranding newvers.sh"
    sed -i.sunshine-orig \
        -e 's/^TYPE="FreeBSD"/TYPE="SunshineBSD"/' \
        -e 's/^BRANCH=\"/BRANCH=\"SUNSHINE-/' \
        "$newvers"
fi
if ! grep -q '^TYPE="SunshineBSD"' "$newvers"; then
    echo "brand-freebsd: verification failed: TYPE not rebranded in newvers.sh" >&2
    exit 1
fi

if [ -f "$src/etc/motd.template" ] || [ -d "$src/etc" ]; then
    echo "brand-freebsd: installing SunshineBSD motd template"
    cp "$root_dir/branding/motd" "$src/etc/motd.template"
    if ! grep -q "SunshineBSD" "$src/etc/motd.template"; then
        echo "brand-freebsd: verification failed: motd template" >&2
        exit 1
    fi
else
    echo "brand-freebsd: note: no etc/ in source tree; skipping motd"
fi

echo "brand-freebsd: done. This tree now identifies as a SunshineBSD fork of FreeBSD."

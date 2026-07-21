#!/bin/sh
# pack-dist.sh -- fan the staged SunshineBSD payload out to both consumers.
# One job: mirror $SUNISO_STAGE onto the live tree (so booting the ISO in
# a VM sees everything) AND pack it into usr/freebsd-dist/sunshine.txz
# with a matching MANIFEST entry (so a real bsdinstall run installs it).
# bsdinstall does not clone the live ISO filesystem onto a target disk;
# it extracts usr/freebsd-dist/*.txz (see the MANIFEST-driven
# distribution-set selector in usr/libexec/bsdinstall/auto). A live tree
# with sunconfig etc. sitting only in the tree would work for booting
# this ISO in a VM but vanish the moment someone actually installs from
# it. Both paths come from the single staged source instead of
# duplicated install logic that could drift apart.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_STAGE SUNISO_TREE SUNISO_TXZ
init_sha256
txz_flag=$(txz_flag_for "$SUNISO_TXZ")

log "mirroring the SunshineBSD payload onto the live tree"
cp -Rp "$SUNISO_STAGE/." "$SUNISO_TREE/"

log "packing sunshine.txz ($SUNISO_TXZ, installed distribution set)"
sunshine_txz="$SUNISO_TREE/usr/freebsd-dist/sunshine.txz"
log "  payload size: $(du -sh "$SUNISO_STAGE" 2>/dev/null | cut -f 1)"
# --uid/--gname 0/root: $SUNISO_STAGE was built by whatever unprivileged
# user is running this script, so bsdtar would otherwise record *that*
# user's numeric uid/gid in the archive (confirmed real bsdtar 3.8.4
# behavior: create-mode ownership defaults to what's on disk). On a real
# bsdinstall extraction that would leave every SunshineBSD file owned by
# an arbitrary build-host uid instead of root. base.txz doesn't need this
# because it's built by FreeBSD's own release process running as root.
#
# Compression of a tree this size (Xfce + Qt6/KDE bits pulled in by sddm)
# can run long with zero output, especially at xz's default level;
# backgrounded here so this loop can print a status line every 10 seconds
# instead of leaving the build looking hung.
bsdtar -c "$txz_flag" -f "$sunshine_txz" --uid 0 --uname root --gid 0 --gname root \
    -C "$SUNISO_STAGE" . &
bsdtar_pid=$!
elapsed=0
while kill -0 "$bsdtar_pid" 2>/dev/null; do
    sleep 10
    elapsed=$((elapsed + 10))
    size_now=$(du -h "$sunshine_txz" 2>/dev/null | cut -f 1)
    log "  ...still packing sunshine.txz (${elapsed}s elapsed, ${size_now:-0} written so far)"
done
wait "$bsdtar_pid"
log "  sunshine.txz done: $(du -h "$sunshine_txz" | cut -f 1)"
sunshine_sha256=$(sha256_of "$sunshine_txz")
sunshine_size=$(du -k "$sunshine_txz" | cut -f 1)
manifest="$SUNISO_TREE/usr/freebsd-dist/MANIFEST"
# "on": pre-checked by default in bsdinstall's real distribution-set
# checklist (usr/libexec/bsdinstall/auto reads this MANIFEST column
# directly into `dialog --checklist`'s initial state) -- the desktop
# stack is what SunshineBSD ships, not an opt-in extra. Unlike
# base.txz/kernel.txz (hardcoded into $DISTRIBUTIONS and never even
# shown as a checkbox, per usr/libexec/bsdinstall/auto), this is a real,
# selectable checklist entry that merely starts checked -- a user can
# still uncheck it, so it's not truly mandatory the way those two are.
grep -v '^sunshine\.txz	' "$manifest" > "$manifest.$$" 2>/dev/null || true
printf 'sunshine.txz\t%s\t%s\tsunshine\t"SunshineBSD desktop stack (Xfce, SDDM, dbus, polkit, fonts, native tooling)"\ton\n' \
    "$sunshine_sha256" "$sunshine_size" >> "$manifest.$$"
mv "$manifest.$$" "$manifest"

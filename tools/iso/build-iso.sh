#!/bin/sh
# build-iso.sh -- rebuild the finished tree into a bootable ISO.
# One job: xorriso the branded, fully staged $SUNISO_TREE into a
# BIOS+UEFI bootable image in $SUNISO_DIST, using the boot images
# fetch-base.sh recorded in $SUNISO_WORK/boot-images.env.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_ROOT SUNISO_TREE SUNISO_DIST SUNISO_ARCH SUNISO_NUMVER SUNISO_WORK
init_sha256

if [ ! -f "$SUNISO_WORK/boot-images.env" ]; then
    fail "boot-images.env missing -- fetch-base.sh must run first"
fi
. "$SUNISO_WORK/boot-images.env"

# Keep the upstream volume label: the ISO's own /etc/fstab mounts root
# by that label, so changing it would break boot.
label=$(sed -n 's|^/dev/iso9660/\([^ 	]*\).*|\1|p' "$SUNISO_TREE/etc/fstab" | head -n 1)
if [ -z "$label" ]; then
    label="SUNSHINEBSD_$(echo "$SUNISO_NUMVER" | tr . _)"
    log "warning: no iso9660 label in etc/fstab; using $label"
fi

mkdir -p "$SUNISO_DIST"
# Derive the filename from branding/version instead of a second hardcoded
# copy, so a version bump can't leave the two out of sync.
release_line=$(cat "$SUNISO_ROOT/branding/version")
sunshine_ver=${release_line#SunshineBSD }
out="$SUNISO_DIST/sunshinebsd-$sunshine_ver-$SUNISO_ARCH.iso"
log "building $out (label $label)"

case "$bios_img" in
    "$SUNISO_TREE"/*) bios_arg="boot/cdboot" ;;
    *)
        cp "$bios_img" "$SUNISO_TREE/boot/cdboot.eltorito"
        bios_arg="boot/cdboot.eltorito"
        ;;
esac

# -uid 0 -gid 0: the tree was extracted as an unprivileged user, but the
# live system's init checks that files like /etc/login.conf are owned by
# root; record root ownership in the RockRidge metadata.
if [ -n "$uefi_img" ]; then
    cp "$uefi_img" "$SUNISO_TREE/boot/efiboot.img"
    xorriso -as mkisofs -o "$out" -V "$label" -rock -joliet-long \
        -uid 0 -gid 0 \
        -b "$bios_arg" -no-emul-boot \
        -eltorito-alt-boot -e boot/efiboot.img -no-emul-boot \
        "$SUNISO_TREE"
else
    log "warning: no UEFI boot image found; BIOS boot only"
    xorriso -as mkisofs -o "$out" -V "$label" -rock -joliet-long \
        -uid 0 -gid 0 \
        -b "$bios_arg" -no-emul-boot \
        "$SUNISO_TREE"
fi

log "done."
log "  $out"
log "  SHA256 $(sha256_of "$out")"
log "boot it with: make qemu-iso"

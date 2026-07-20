#!/bin/sh
# fetch-base.sh -- download, verify, and extract the upstream FreeBSD ISO.
# One job: get a pristine, checksum-verified upstream tree into
# $SUNISO_TREE and the El Torito boot images into $SUNISO_WORK/bootimg,
# recording which BIOS/UEFI images were found in
# $SUNISO_WORK/boot-images.env for build-iso.sh to consume at the end.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_CACHE SUNISO_WORK SUNISO_TREE \
    SUNISO_VERSION SUNISO_ARCH SUNISO_FLAVOR SUNISO_MIRROR SUNISO_NUMVER
init_sha256

iso_name="FreeBSD-$SUNISO_VERSION-$SUNISO_ARCH-$SUNISO_FLAVOR.iso"
sum_name="CHECKSUM.SHA256-FreeBSD-$SUNISO_VERSION-$SUNISO_ARCH"
base_url="$SUNISO_MIRROR/releases/$SUNISO_ARCH/$SUNISO_ARCH/ISO-IMAGES/$SUNISO_NUMVER"

# --- download + verify --------------------------------------------------

mkdir -p "$SUNISO_CACHE"
if [ ! -f "$SUNISO_CACHE/$iso_name" ]; then
    log "downloading $base_url/$iso_name"
    # $$ suffix so two concurrent runs cannot clobber each other's download
    curl -fL --proto '=https' -o "$SUNISO_CACHE/$iso_name.part.$$" "$base_url/$iso_name"
    mv "$SUNISO_CACHE/$iso_name.part.$$" "$SUNISO_CACHE/$iso_name"
fi
log "fetching checksums"
curl -fL --proto '=https' -o "$SUNISO_CACHE/$sum_name" "$base_url/$sum_name"

# Checksum line format: SHA256 (FreeBSD-...iso) = <hash>
want=$(grep -F "($iso_name)" "$SUNISO_CACHE/$sum_name" | sed -n 's/.*= *//p' | head -n 1)
if [ -z "$want" ]; then
    fail "$iso_name not found in $sum_name"
fi
got=$(sha256_of "$SUNISO_CACHE/$iso_name")
if [ "$want" != "$got" ]; then
    echo "make-iso: SHA256 mismatch for $iso_name" >&2
    echo "make-iso:   want $want" >&2
    echo "make-iso:   got  $got" >&2
    exit 1
fi
log "checksum verified ($got)"

# --- extract ------------------------------------------------------------

log "extracting ISO"
if [ -d "$SUNISO_WORK" ]; then
    chmod -R u+w "$SUNISO_WORK" 2>/dev/null || true
    rm -rf "$SUNISO_WORK"
fi
mkdir -p "$SUNISO_TREE"
bsdtar -xf "$SUNISO_CACHE/$iso_name" -C "$SUNISO_TREE"
chmod -R u+w "$SUNISO_TREE"

log "extracting El Torito boot images"
mkdir -p "$SUNISO_WORK/bootimg"
xorriso -osirrox on -indev "$SUNISO_CACHE/$iso_name" \
    -extract_boot_images "$SUNISO_WORK/bootimg" >/dev/null 2>&1
uefi_img=""
for f in "$SUNISO_WORK/bootimg/"*uefi*; do
    [ -f "$f" ] && uefi_img="$f" && break
done
bios_img="$SUNISO_TREE/boot/cdboot"
if [ ! -f "$bios_img" ]; then
    for f in "$SUNISO_WORK/bootimg/"*bios*; do
        [ -f "$f" ] && bios_img="$f" && break
    done
fi
if [ ! -f "$bios_img" ]; then
    fail "no BIOS boot image found"
fi

# Hand the discovered image paths to build-iso.sh (the only later step
# that needs them) without re-probing.
{
    echo "bios_img='$bios_img'"
    echo "uefi_img='$uefi_img'"
} > "$SUNISO_WORK/boot-images.env"

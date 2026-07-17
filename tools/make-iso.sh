#!/bin/sh
# make-iso.sh — produce a bootable SunshineBSD ISO by remastering the
# pinned upstream FreeBSD release ISO (Stage 0).
#
# One job: download + verify the official FreeBSD ISO, apply SunshineBSD
# identity and tooling on top, and rebuild a BIOS+UEFI bootable ISO in
# dist/. This is the Stage 0 test path: it produces something bootable
# in QEMU today. The real from-source ISO comes from `make world` +
# `make image` once a FreeBSD build host is available.
#
# Runs on Linux (incl. WSL) or FreeBSD. Needs: curl, bsdtar, xorriso,
# sha256sum (or sha256).
#
# usage: tools/make-iso.sh
#
# Environment:
#   FREEBSD_ISO_VERSION  upstream release to remaster (default: 14.3-RELEASE)
#   FREEBSD_ISO_ARCH     architecture (default: amd64)
#   FREEBSD_ISO_FLAVOR   disc1 | bootonly | dvd1 (default: disc1)
#   FREEBSD_ISO_MIRROR   base URL (default: https://download.freebsd.org)
#   SUNSHINE_ISO_WORK    scratch dir (default: ~/.cache/sunshinebsd/iso-build)

set -eu

VERSION="${FREEBSD_ISO_VERSION:-14.3-RELEASE}"
ARCH="${FREEBSD_ISO_ARCH:-amd64}"
FLAVOR="${FREEBSD_ISO_FLAVOR:-disc1}"
MIRROR="${FREEBSD_ISO_MIRROR:-https://download.freebsd.org}"

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="${SUNSHINE_ISO_WORK:-$HOME/.cache/sunshinebsd/iso-build}"
cache="$HOME/.cache/sunshinebsd/downloads"
tree="$work/tree"
dist="$root_dir/dist"

for tool in curl bsdtar xorriso; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "make-iso: missing tool: $tool" >&2
        echo "make-iso: on Fedora: dnf install curl bsdtar xorriso" >&2
        exit 1
    }
done
if command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v sha256 >/dev/null 2>&1; then
    sha256_of() { sha256 -q "$1"; }
else
    echo "make-iso: need sha256sum or sha256" >&2
    exit 1
fi

numver="${VERSION%%-*}"
iso_name="FreeBSD-$VERSION-$ARCH-$FLAVOR.iso"
sum_name="CHECKSUM.SHA256-FreeBSD-$VERSION-$ARCH"
base_url="$MIRROR/releases/$ARCH/$ARCH/ISO-IMAGES/$numver"

# --- 1. download + verify --------------------------------------------

mkdir -p "$cache"
if [ ! -f "$cache/$iso_name" ]; then
    echo "make-iso: downloading $base_url/$iso_name"
    # $$ suffix so two concurrent runs cannot clobber each other's download
    curl -fL --proto '=https' -o "$cache/$iso_name.part.$$" "$base_url/$iso_name"
    mv "$cache/$iso_name.part.$$" "$cache/$iso_name"
fi
echo "make-iso: fetching checksums"
curl -fL --proto '=https' -o "$cache/$sum_name" "$base_url/$sum_name"

# Checksum line format: SHA256 (FreeBSD-...iso) = <hash>
want=$(grep -F "($iso_name)" "$cache/$sum_name" | sed -n 's/.*= *//p' | head -n 1)
if [ -z "$want" ]; then
    echo "make-iso: $iso_name not found in $sum_name" >&2
    exit 1
fi
got=$(sha256_of "$cache/$iso_name")
if [ "$want" != "$got" ]; then
    echo "make-iso: SHA256 mismatch for $iso_name" >&2
    echo "make-iso:   want $want" >&2
    echo "make-iso:   got  $got" >&2
    exit 1
fi
echo "make-iso: checksum verified ($got)"

# --- 2. extract -------------------------------------------------------

echo "make-iso: extracting ISO"
if [ -d "$work" ]; then
    chmod -R u+w "$work" 2>/dev/null || true
    rm -rf "$work"
fi
mkdir -p "$tree"
bsdtar -xf "$cache/$iso_name" -C "$tree"
chmod -R u+w "$tree"

echo "make-iso: extracting El Torito boot images"
mkdir -p "$work/bootimg"
xorriso -osirrox on -indev "$cache/$iso_name" \
    -extract_boot_images "$work/bootimg" >/dev/null 2>&1
uefi_img=""
for f in "$work/bootimg/"*uefi*; do
    [ -f "$f" ] && uefi_img="$f" && break
done
bios_img="$tree/boot/cdboot"
if [ ! -f "$bios_img" ]; then
    for f in "$work/bootimg/"*bios*; do
        [ -f "$f" ] && bios_img="$f" && break
    done
fi
if [ ! -f "$bios_img" ]; then
    echo "make-iso: no BIOS boot image found" >&2
    exit 1
fi

# --- 3. brand ---------------------------------------------------------

echo "make-iso: applying SunshineBSD identity"

cp "$root_dir/branding/motd" "$tree/etc/motd" 2>/dev/null || true
cp "$root_dir/branding/motd" "$tree/etc/motd.template"

release_line=$(cat "$root_dir/branding/version")
{
    echo "$release_line"
    echo "Remastered from FreeBSD-$VERSION-$ARCH-$FLAVOR (Stage 0 test image)"
} > "$tree/etc/sunshine-release"

# uname branding: from-source builds get TYPE="SunshineBSD" compiled in
# via brand-freebsd.sh, but this remastered ISO boots the upstream
# binary kernel. FreeBSD uname(1) honors UNAME_* environment overrides,
# so wrap the binary itself — profile-based exports would miss
# non-login shells such as the installer's shell escape. UNAME_r stays
# untouched because third-party software parses it for the underlying
# FreeBSD release.
if [ ! -f "$tree/usr/bin/uname.freebsd" ]; then
    mv "$tree/usr/bin/uname" "$tree/usr/bin/uname.freebsd"
fi
cat > "$tree/usr/bin/uname" <<EOF
#!/bin/sh
# SunshineBSD uname wrapper (added by tools/make-iso.sh). The real
# binary honors these documented environment overrides; existing
# UNAME_* values set by the caller win.
[ -z "\${UNAME_s:-}" ] && { UNAME_s="SunshineBSD"; export UNAME_s; }
[ -z "\${UNAME_v:-}" ] && {
    UNAME_v="$release_line (remastered FreeBSD-$VERSION kernel)"
    export UNAME_v
}
exec /usr/bin/uname.freebsd "\$@"
EOF
chmod 0555 "$tree/usr/bin/uname"

mkdir -p "$tree/boot/lua"
cp "$root_dir/branding/loader/brand-sunshine.lua" "$tree/boot/lua/brand-sunshine.lua"

cat >> "$tree/boot/loader.conf" <<'EOF'

# --- SunshineBSD branding (added by tools/make-iso.sh) ---
loader_menu_title="Welcome to SunshineBSD"
loader_brand="sunshine"
boot_multicons="YES"
console="comconsole,vidconsole"
EOF

# --- 4. install SunshineBSD tooling ----------------------------------

echo "make-iso: installing sunconfig and rc2runit"
share="$tree/usr/local/share/sunconfig"
sbin="$tree/usr/local/sbin"
mkdir -p "$share" "$sbin" "$tree/etc/sunshine" \
    "$tree/usr/local/share/doc/sunshinebsd"

cp "$root_dir/src/sunconfig/sunconfig" "$share/sunconfig.lua"
cp -R "$root_dir/src/sunconfig/lib" "$share/lib"
cat > "$sbin/sunconfig" <<'EOF'
#!/bin/sh
# SunshineBSD sunconfig launcher: uses the base-system Lua (flua).
exec /usr/libexec/flua /usr/local/share/sunconfig/sunconfig.lua "$@"
EOF
chmod 0755 "$sbin/sunconfig"

cp "$root_dir/src/rc-compat/rc2runit" "$sbin/rc2runit"
chmod 0755 "$sbin/rc2runit"

cp "$root_dir/src/sunsnap/sunsnap" "$sbin/sunsnap"
chmod 0755 "$sbin/sunsnap"

echo "make-iso: installing flesk"
fshare="$tree/usr/local/share/flesk"
mkdir -p "$fshare"
cp "$root_dir/src/flesk/flesk" "$fshare/flesk.lua"
cp -R "$root_dir/src/flesk/lib" "$fshare/lib"
cat > "$sbin/flesk" <<'EOF'
#!/bin/sh
# SunshineBSD flesk launcher: uses the base-system Lua (flua).
exec /usr/libexec/flua /usr/local/share/flesk/flesk.lua "$@"
EOF
chmod 0755 "$sbin/flesk"

mkdir -p "$tree/etc/sunshine/zsh"
cp "$root_dir/branding/zshrc" "$tree/etc/sunshine/zsh/zshrc"

cp "$root_dir/examples/etc-sunshine/"*.lua "$tree/etc/sunshine/"
cp "$root_dir/PLAN.md" "$root_dir/DOCS/"*.MD \
    "$tree/usr/local/share/doc/sunshinebsd/"

# --- 5. rebuild the ISO ----------------------------------------------

# Keep the upstream volume label: the ISO's own /etc/fstab mounts root
# by that label, so changing it would break boot.
label=$(sed -n 's|^/dev/iso9660/\([^ 	]*\).*|\1|p' "$tree/etc/fstab" | head -n 1)
if [ -z "$label" ]; then
    label="SUNSHINEBSD_$(echo "$numver" | tr . _)"
    echo "make-iso: warning: no iso9660 label in etc/fstab; using $label"
fi

mkdir -p "$dist"
# Derive the filename from branding/version instead of a second hardcoded
# copy, so a version bump can't leave the two out of sync.
sunshine_ver=${release_line#SunshineBSD }
out="$dist/sunshinebsd-$sunshine_ver-$ARCH.iso"
echo "make-iso: building $out (label $label)"

case "$bios_img" in
    "$tree"/*) bios_arg="boot/cdboot" ;;
    *)
        cp "$bios_img" "$tree/boot/cdboot.eltorito"
        bios_arg="boot/cdboot.eltorito"
        ;;
esac

# -uid 0 -gid 0: the tree was extracted as an unprivileged user, but the
# live system's init checks that files like /etc/login.conf are owned by
# root; record root ownership in the RockRidge metadata.
if [ -n "$uefi_img" ]; then
    cp "$uefi_img" "$tree/boot/efiboot.img"
    xorriso -as mkisofs -o "$out" -V "$label" -rock -joliet-long \
        -uid 0 -gid 0 \
        -b "$bios_arg" -no-emul-boot \
        -eltorito-alt-boot -e boot/efiboot.img -no-emul-boot \
        "$tree"
else
    echo "make-iso: warning: no UEFI boot image found; BIOS boot only"
    xorriso -as mkisofs -o "$out" -V "$label" -rock -joliet-long \
        -uid 0 -gid 0 \
        -b "$bios_arg" -no-emul-boot \
        "$tree"
fi

echo "make-iso: done."
echo "make-iso:   $out"
echo "make-iso:   SHA256 $(sha256_of "$out")"
echo "make-iso: boot it with: make qemu-iso"

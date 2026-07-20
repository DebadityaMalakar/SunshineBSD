#!/bin/sh
# brand-tree.sh -- apply SunshineBSD identity to the extracted live tree.
# One job: motd, /etc/sunshine-release, the uname wrapper, the loader
# logo/branding, and the loader.conf console settings on $SUNISO_TREE.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_ROOT SUNISO_TREE SUNISO_VERSION SUNISO_ARCH SUNISO_FLAVOR

log "applying SunshineBSD identity"

cp "$SUNISO_ROOT/branding/motd" "$SUNISO_TREE/etc/motd" 2>/dev/null || true
cp "$SUNISO_ROOT/branding/motd" "$SUNISO_TREE/etc/motd.template"

release_line=$(cat "$SUNISO_ROOT/branding/version")
{
    echo "$release_line"
    echo "Remastered from FreeBSD-$SUNISO_VERSION-$SUNISO_ARCH-$SUNISO_FLAVOR (Stage 0 test image)"
} > "$SUNISO_TREE/etc/sunshine-release"

# uname branding: from-source builds get TYPE="SunshineBSD" compiled in
# via brand-freebsd.sh, but this remastered ISO boots the upstream
# binary kernel. FreeBSD uname(1) honors UNAME_* environment overrides,
# so wrap the binary itself -- profile-based exports would miss
# non-login shells such as the installer's shell escape. UNAME_r stays
# untouched because third-party software parses it for the underlying
# FreeBSD release.
if [ ! -f "$SUNISO_TREE/usr/bin/uname.freebsd" ]; then
    mv "$SUNISO_TREE/usr/bin/uname" "$SUNISO_TREE/usr/bin/uname.freebsd"
fi
cat > "$SUNISO_TREE/usr/bin/uname" <<EOF
#!/bin/sh
# SunshineBSD uname wrapper (added by the ISO build,
# tools/iso/brand-tree.sh). The real binary honors these documented
# environment overrides; existing UNAME_* values set by the caller win.
[ -z "\${UNAME_s:-}" ] && { UNAME_s="SunshineBSD"; export UNAME_s; }
[ -z "\${UNAME_v:-}" ] && {
    UNAME_v="$release_line (remastered FreeBSD-$SUNISO_VERSION kernel)"
    export UNAME_v
}
exec /usr/bin/uname.freebsd "\$@"
EOF
chmod 0555 "$SUNISO_TREE/usr/bin/uname"

mkdir -p "$SUNISO_TREE/boot/lua"
cp "$SUNISO_ROOT/branding/loader/gfx-sunshine.lua" "$SUNISO_TREE/boot/lua/gfx-sunshine.lua"

cat >> "$SUNISO_TREE/boot/loader.conf" <<'EOF'

# --- SunshineBSD branding (added by the ISO build, tools/iso/brand-tree.sh) ---
loader_menu_title="Welcome to SunshineBSD"
loader_brand="sunshine"
loader_logo="sunshine"
boot_multicons="YES"
console="comconsole,vidconsole"

# vt(4) picks its console backend (plain VGA text vs. a real VBE/VESA
# linear framebuffer) once, during early boot attach -- before userland
# runs, and before anything can kldload a module to influence it.
# Live-tested 2026-07-18: with vesa.ko absent at boot, vt(4) attaches in
# text-only mode, xf86-video-scfb's probe finds no framebuffer device at
# all ("No devices detected" / "no screens found"), and `kldload vesa`
# *after* boot has zero effect on an already-attached console -- only
# loading it before vt(4) probes (via loader.conf, here) makes vt(4)
# choose the VBE backend and expose a framebuffer scfb can use.
vesa_load="YES"
EOF

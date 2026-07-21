#!/bin/sh
# stage-tooling.sh -- stage SunshineBSD's own native payload.
# One job: everything this project itself ships -- sunconfig, rc2runit,
# sunsnap, flesk, flash, the sysaccounts provisioning scripts, the zsh
# defaults, the example /etc/sunshine configuration, the docs, the empty
# /home mountpoint, and the sunconfig-generated runit /service tree --
# into $SUNISO_STAGE. Third-party packages are stage-packages.sh's job;
# the rc(8) boot chain is stage-boot-chain.sh's.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_ROOT SUNISO_STAGE SUNISO_WORK SUNISO_LUA

log "installing sunconfig and rc2runit"
share="$SUNISO_STAGE/usr/local/share/sunconfig"
sbin="$SUNISO_STAGE/usr/local/sbin"
mkdir -p "$share" "$sbin" "$SUNISO_STAGE/etc/sunshine" \
    "$SUNISO_STAGE/usr/local/share/doc/sunshinebsd"

# Empty /home mountpoint, baked in here (while $SUNISO_STAGE is still
# writable) specifically so it can exist at all on the live/install ISO:
# confirmed live 2026-07-19 that /home is entirely absent from the stock
# FreeBSD tree, and mounting anything -- mdmfs, unionfs, whatever --
# requires an existing directory to mount onto. supser's homedir creation
# (provision-accounts) failed outright with "install: mkdir /home:
# Read-only file system" without this. See stage-boot-chain.sh's
# etc/rc.d/sunshine_etc_overlay, which mdmfs+unionfs-mounts a writable
# layer over this at boot, the same mechanism used for /etc.
mkdir -p "$SUNISO_STAGE/home"

cp "$SUNISO_ROOT/src/sunconfig/sunconfig" "$share/sunconfig.lua"
cp -R "$SUNISO_ROOT/src/sunconfig/lib" "$share/lib"
cat > "$sbin/sunconfig" <<'EOF'
#!/bin/sh
# SunshineBSD sunconfig launcher: uses the base-system Lua (flua).
exec /usr/libexec/flua /usr/local/share/sunconfig/sunconfig.lua "$@"
EOF
chmod 0755 "$sbin/sunconfig"

cp "$SUNISO_ROOT/src/rc-compat/rc2runit" "$sbin/rc2runit"
chmod 0755 "$sbin/rc2runit"

cp "$SUNISO_ROOT/src/sunsnap/sunsnap" "$sbin/sunsnap"
chmod 0755 "$sbin/sunsnap"

log "installing flesk"
fshare="$SUNISO_STAGE/usr/local/share/flesk"
mkdir -p "$fshare" "$SUNISO_STAGE/usr/bin"
cp "$SUNISO_ROOT/src/flesk/flesk" "$fshare/flesk.lua"
cp -R "$SUNISO_ROOT/src/flesk/lib" "$fshare/lib"
# /usr/bin, not /usr/local/sbin: on the live ISO this needs to run from
# the installer's shell escape, which execs a plain non-login /bin/sh
# and so never sources /root/.profile's PATH (which does list
# /usr/local/sbin, but only for a properly logged-in shell); on an
# installed system /usr/bin is on PATH either way.
cat > "$SUNISO_STAGE/usr/bin/flesk" <<'EOF'
#!/bin/sh
# SunshineBSD flesk launcher: uses the base-system Lua (flua).
exec /usr/libexec/flua /usr/local/share/flesk/flesk.lua "$@"
EOF
chmod 0755 "$SUNISO_STAGE/usr/bin/flesk"

log "installing flash"
ashare="$SUNISO_STAGE/usr/local/share/flash"
mkdir -p "$ashare"
cp "$SUNISO_ROOT/src/flash/flash" "$ashare/flash.lua"
cp -R "$SUNISO_ROOT/src/flash/lib" "$ashare/lib"
cat > "$SUNISO_STAGE/usr/bin/flash" <<'EOF'
#!/bin/sh
# SunshineBSD flash launcher: uses the base-system Lua (flua).
exec /usr/libexec/flua /usr/local/share/flash/flash.lua "$@"
EOF
chmod 0755 "$SUNISO_STAGE/usr/bin/flash"

log "installing provision-procfs, provision-accounts, provision-pkgfiles, provision-gpu, etc-overlay, and sddm-launch"
cp "$SUNISO_ROOT/src/sysaccounts/provision-procfs" "$sbin/sunshine-provision-procfs"
chmod 0755 "$sbin/sunshine-provision-procfs"
cp "$SUNISO_ROOT/src/sysaccounts/provision-accounts" "$sbin/sunshine-provision-accounts"
chmod 0755 "$sbin/sunshine-provision-accounts"
cp "$SUNISO_ROOT/src/sysaccounts/provision-pkgfiles" "$sbin/sunshine-provision-pkgfiles"
chmod 0755 "$sbin/sunshine-provision-pkgfiles"
cp "$SUNISO_ROOT/src/sysaccounts/provision-gpu" "$sbin/sunshine-provision-gpu"
chmod 0755 "$sbin/sunshine-provision-gpu"
cp "$SUNISO_ROOT/src/sysaccounts/etc-overlay" "$sbin/sunshine-etc-overlay"
chmod 0755 "$sbin/sunshine-etc-overlay"
cp "$SUNISO_ROOT/src/sysaccounts/sddm-launch" "$sbin/sunshine-sddm"
chmod 0755 "$sbin/sunshine-sddm"

mkdir -p "$SUNISO_STAGE/etc/sunshine/zsh"
cp "$SUNISO_ROOT/branding/zshrc" "$SUNISO_STAGE/etc/sunshine/zsh/zshrc"

cp "$SUNISO_ROOT/examples/etc-sunshine/"*.lua "$SUNISO_STAGE/etc/sunshine/"
cp "$SUNISO_ROOT/PLAN.md" "$SUNISO_ROOT/DOCS/"*.MD \
    "$SUNISO_STAGE/usr/local/share/doc/sunshinebsd/"

# --- generate the runit service tree (sunconfig) ------------------------

log "generating runit service tree (sunconfig)"
sunconfig_out="$SUNISO_WORK/sunconfig-out"
"$SUNISO_LUA" "$SUNISO_ROOT/src/sunconfig/sunconfig" build \
    -c "$SUNISO_ROOT/examples/etc-sunshine" -o "$sunconfig_out" >/dev/null
mkdir -p "$SUNISO_STAGE/service"
cp -Rp "$sunconfig_out/service/." "$SUNISO_STAGE/service/"
# cp -p preserves the executable bit sunconfig already set on run
# scripts; re-assert it too, since intermediate copies don't always
# preserve permission bits identically across hosts.
find "$SUNISO_STAGE/service" -type f -name run -exec chmod 0755 {} +

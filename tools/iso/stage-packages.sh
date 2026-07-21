#!/bin/sh
# stage-packages.sh -- stage the third-party desktop-session packages.
# One job: fetch the pinned package set (plus full transitive dependency
# closure) from the live FreeBSD pkg repo into $SUNISO_STAGE via
# tools/fetch-pkg.sh, and write the xorg.conf.d snippet that makes the
# fetched scfb driver actually get used.
#
# Internal build step -- run via tools/make-iso.sh, which exports every
# SUNISO_* variable below.
#
# Package rationale (every entry verified against the live repo, dates
# noted -- none of this is guessed):
# - dbus + polkit + consolekit2: PLAN-03.MD's seat backend, chosen over
#   elogind which has no FreeBSD package on any current branch. Run
#   under rc(8), not runit -- see stage-boot-chain.sh.
# - upower (origin sysutils/upower, confirmed real 2026-07-19): not a
#   dependency of the xfce meta-port -- xfce4-power-manager degrades
#   without it but logs D-Bus activation failures every session (seen
#   live while debugging the session collapse).
# - runit: supervises everything sunconfig generates into
#   $SUNISO_STAGE/service (see stage-tooling.sh).
# - xorg-server, sddm, xfce (meta-port x11-wm/xfce4), thunar: the
#   PLAN-03.MD "XFCE + SDDM + Xorg" stage. The xfce meta-port does NOT
#   pull in thunar on FreeBSD, unlike most Linux distros' Xfce
#   metapackages -- confirmed 2026-07-18 against the live pkg repo.
# - xf86-video-scfb: found live-testing this stage that xorg-server's
#   own dependency list (17 packages, confirmed via the real repo)
#   pulls in libdrm but NOT a single xf86-video-* driver -- X.Org video
#   drivers are always separate loadable packages, never a server
#   dependency. drm-kmod is deliberately deferred (see PLAN-03.MD's
#   Open Questions), so without an explicit fallback driver Xorg had
#   nothing to render with at all and died immediately ("Failed to
#   read display number from pipe"). scfb is FreeBSD's
#   hardware-independent syscons framebuffer driver -- the standard
#   unaccelerated fallback for generic hardware/VMs.
# - xf86-input-libinput (confirmed real 2026-07-18): X.Org input
#   drivers are separate packages too, same as video drivers --
#   confirmed NOT a dependency of xorg-server. Without it, Xorg has no
#   way to translate the real mouse/keyboard into X input events at
#   all, which live-tested as: SDDM's greeter renders once, then the
#   pointer never moves again and nothing responds to input, forever --
#   actually just Xorg and the greeter both quietly idling (confirmed
#   via `top`: sddm-greeter-qt6 at 0.00% CPU in `select`) because there
#   was genuinely nothing for either to receive. Unlike scfb, needs no
#   xorg.conf.d forcing -- Xorg's input autoconfiguration picks up any
#   available input driver for the keyboard/mouse device classes.
# - xinit (origin x11/xinit, confirmed real 2026-07-18): ships
#   /usr/local/bin/startx + xinit -- not a dependency of xorg-server or
#   sddm, needed explicitly so `flash start xfce` can launch Xfce
#   directly, bypassing SDDM entirely (see src/flash/lib/start.lua's
#   plan_xfce).
# - ncurses (origin devel/ncurses, confirmed real 2026-07-18): not
#   consumed by anything yet, staged ahead of need for upcoming
#   terminal-UI work.
# - htop: user-requested system monitor, standalone.
# - drm-61-kmod (origin graphics/drm-61-kmod, confirmed live 2026-07-21
#   against the FreeBSD:14:amd64 repo): ships i915kms.ko and friends --
#   the kernel modesetting side of GPU acceleration. Deliberately NOT
#   the graphics/drm-kmod metaport: that pulls gpu-firmware-kmod, whose
#   dependency list is ~180 firmware packages for every AMD/Radeon chip
#   ever made; this stage ships Intel only (user decision 2026-07-21),
#   so the kmod plus the 14 gpu-firmware-intel-kmod-* packages (all of
#   them, ~5 MB total, listed from the live index the same day) is the
#   whole set. The GL userland needs nothing extra: xorg-server's own
#   dependency closure already pulls mesa-dri + mesa-libs (confirmed
#   live 2026-07-21), which include the Intel iris/crocus DRI drivers.
#   The repo's kmod is built against __FreeBSD_version 1404000 (14.4),
#   which is why make-iso.sh remasters 14.4-RELEASE (bumped from 14.3
#   the same day, 2026-07-21, so the kernel matches the kmod). If the
#   pairing ever skews again, sunshine-provision-gpu (which does the
#   actual kldload at boot -- nothing here loads anything) falls back
#   to scfb + software rendering rather than breaking the boot.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/lib.sh"

require_env SUNISO_ROOT SUNISO_STAGE SUNISO_ARCH SUNISO_NUMVER SUNISO_LUA

pkg_abi_rel="${SUNISO_NUMVER%%.*}"
log "installing desktop-session packages (dbus, polkit, consolekit2, upower, runit, xorg-server, xf86-video-scfb, xf86-input-libinput, sddm, xfce, thunar, ncurses, xinit, htop, drm-61-kmod + Intel GPU firmware)"
PKG_ABI="FreeBSD:${pkg_abi_rel}:${SUNISO_ARCH}" LUA="$SUNISO_LUA" \
    sh "$SUNISO_ROOT/tools/fetch-pkg.sh" "$SUNISO_STAGE" \
    dbus polkit consolekit2 upower runit xorg-server xf86-video-scfb xf86-input-libinput sddm xfce thunar ncurses xinit htop \
    drm-61-kmod \
    gpu-firmware-intel-kmod-alderlake gpu-firmware-intel-kmod-battlemage \
    gpu-firmware-intel-kmod-broxton gpu-firmware-intel-kmod-cannonlake \
    gpu-firmware-intel-kmod-dg1 gpu-firmware-intel-kmod-dg2 \
    gpu-firmware-intel-kmod-elkhartlake gpu-firmware-intel-kmod-geminilake \
    gpu-firmware-intel-kmod-icelake gpu-firmware-intel-kmod-kabylake \
    gpu-firmware-intel-kmod-meteorlake gpu-firmware-intel-kmod-rocketlake \
    gpu-firmware-intel-kmod-skylake gpu-firmware-intel-kmod-tigerlake

# Fetching xf86-video-scfb is not the same as Xorg actually choosing to
# use it: Xorg's autoconfiguration matches PCI vendor/device IDs against
# known DDX drivers, and scfb is deliberately *not* PCI-ID-matched (it's
# the syscons/vt-framebuffer fallback, meant for exactly the case where
# no GPU-specific driver applies) -- so autoprobe can fail to find any
# driver at all and Xorg exits immediately, which is exactly the failure
# live-tested 2026-07-18 ("Failed to read display number from pipe"),
# reproduced identically even after scfb was fetched. Forcing the driver
# by name in a config snippet is the standard, universal fix (same
# mechanism on every X.Org platform, not FreeBSD-specific) -- Xorg reads
# every *.conf under xorg.conf.d in order, no restart or package
# reinstall needed to pick it up.
#
# This baked snippet is only the build-time DEFAULT (scfb, safe
# everywhere): sunshine-provision-gpu rewrites the same file at every
# boot after probing the hardware -- Driver "modesetting" when a KMS GPU
# actually attached (i915kms, hardware GL), this scfb content otherwise.
# Named 10-video.conf, not 10-scfb.conf, because its content is a
# boot-time decision, not always scfb.
log "writing the default video driver snippet (scfb; provision-gpu rewrites at boot)"
mkdir -p "$SUNISO_STAGE/usr/local/etc/X11/xorg.conf.d"
cat > "$SUNISO_STAGE/usr/local/etc/X11/xorg.conf.d/10-video.conf" <<'EOF'
# Generated by the SunshineBSD ISO build (tools/iso/stage-packages.sh).
# Forces Xorg onto xf86-video-scfb (FreeBSD's hardware-independent
# syscons framebuffer driver) instead of relying on PCI-ID autoprobe,
# which does not match scfb at all. See PLAN-03.MD's "Xorg video driver"
# row. This is only the safe default: sunshine-provision-gpu rewrites
# this file at boot (Driver "modesetting") when a KMS GPU is attached.
Section "Device"
    Identifier "Card0"
    Driver "scfb"
EndSection
EOF

# Shutdown/restart from inside the Xfce session. x11-wm/xfce4-session's
# own pkg-message (read straight from the package on 2026-07-21) says
# outright that this rules file has to be added by hand, and FreeBSD's
# sysutils/desktop-installer writes exactly this rule in its
# enable_user_shutdown() -- copied from both rather than invented.
# Without it the log-out dialog's Shut Down / Restart buttons are inert:
# consolekit2 answers the seat query, polkit then declines the action
# because no rule authorizes it.
#
# operator is the group desktop-installer uses and FreeBSD's conventional
# group for exactly this; src/sysaccounts/provision-accounts puts the
# default user in it. rules.d's own polkitd:wheel 0700 mode is restored
# at boot by provision-pkgfiles (extraction cannot preserve it).
log "writing the polkit shutdown/restart rules (xfce4-session pkg-message)"
mkdir -p "$SUNISO_STAGE/usr/local/etc/polkit-1/rules.d"
cat > "$SUNISO_STAGE/usr/local/etc/polkit-1/rules.d/51-user-shutdown.rules" <<'EOF'
// Generated by the SunshineBSD ISO build (tools/iso/stage-packages.sh).
// Lets members of the operator group shut down and restart from the
// Xfce log-out dialog. Required by x11-wm/xfce4-session's pkg-message;
// same rule sysutils/desktop-installer installs.
polkit.addRule(function (action, subject) {
    if ((action.id == "org.freedesktop.consolekit.system.restart" ||
         action.id == "org.freedesktop.consolekit.system.stop") &&
        subject.isInGroup("operator")) {
        return polkit.Result.YES;
    }
});
EOF

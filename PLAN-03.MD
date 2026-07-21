# SunshineBSD Desktop Session Plan — XFCE + SDDM under runit

Unlike [PLAN-LUA.MD](PLAN-LUA.MD), this is not cross-cutting — it is
squarely where [PLAN.md](PLAN.md)'s **Stage 1** (modern desktop
experience: XFCE) and **Stage 4** (replace `rc(8)` with runit) meet:
getting a real, boot-to-desktop XFCE session running under SDDM,
entirely supervised by runit, with no `rc.d` anywhere in the chain.
This document is a plan and dependency inventory only — **nothing
described here has been implemented yet.**

## Policy: rc(8) is retired, not parallel

`rc(8)`/`rc.d` is not a second, ongoing service system alongside
runit — it is retired. Every service SunshineBSD itself ships (`dbus`,
`polkit`, the seat backend, `sddm`, and everything else this plan
touches) gets a **native** `/service/<name>/run` script from day one.
`src/rc-compat/rc2runit` exists solely as a legacy-compat shim for
third-party ports that only ship an `rc.d` script and haven't been
natively wired up yet — a stopgap for the migration, not a target
architecture. Nothing described in this document should ever go
through `rc2runit`.

## Goals

- `x11-wm/xfce4` and `x11/sddm` installed and branded as SunshineBSD's
  default desktop session, matching `PLAN.md`'s Foundation Decisions
  (`Desktop: XFCE`) and the terminal/font choices already established
  (`DOCS/ZSH.MD`'s zsh default, Open Sans per `examples/etc-sunshine/
  desktop.lua`).
- SDDM runs as a **native** runit service — its own `/service/sddm/run`
  script, supervised directly, auto-restarted on crash, logged via
  `svlogd` — not wrapped through the transitional `rc2runit` poller
  (`src/rc-compat/rc2runit`). SDDM doesn't need that wrapper (see
  below), and `DOCS/RUNIT.MD` already sketches a `/service/desktop/run`
  example for exactly this kind of service.
- A full boot-to-desktop path that's runit-supervised end to end:
  kernel → `init` → runit → core services (`dbus`, `polkit`, a seat
  backend) → `sddm` → user logs in → `xfce4-session` — matching
  `DOCS/RUNIT.MD`'s existing "system services → desktop environment"
  boot diagram.

## Non-Goals / architecture boundary

- **runit does not supervise XFCE's internal processes**
  (`xfce4-panel`, `xfwm4`, `Thunar`, ...) directly. Those are per-user
  session processes that `xfce4-session` itself spawns and restarts via
  its own autostart/respawn machinery, exactly like every other Xfce
  install anywhere. runit's job stops at "is the SDDM display-manager
  daemon alive" — the same boundary every Unix system draws between
  system-service supervision and per-user session management. Trying
  to make runit supervise individual desktop widgets fights Xfce's own
  architecture for no benefit.
- **Wayland is out of scope.** Xfce's Wayland session is still
  experimental upstream; SDDM + Xfce over Xorg (`x11-servers/
  xorg-server`) is the documented, well-trodden path today. Revisit
  once upstream Xfce Wayland is production-ready.
- **The GUI installer itself is not covered here.** It's also Stage 1
  work, but it's a separate, much larger piece of work. This plan only
  covers getting a working supervised desktop session on a system that
  is already installed.

## Component inventory

`dbus`, `polkit`, and the seat backend rows below were confirmed
2026-07-18 directly against the live FreeBSD:14:amd64 pkg repo
(`packagesite.pkg` + the individual package `+MANIFEST`s); the rest are
typical FreeBSD categorization from memory — **confirm those with
`pkg search` before implementation**, ports get reshuffled between
categories over releases.

| Component | Real package (2026-07-18) | Role |
|-----------|---------------|------|
| XFCE | `xfce` (origin `x11-wm/xfce4`, meta) | Desktop environment: `xfce4-session`, `xfce4-panel`, `xfwm4`, `xfce4-appfinder`, ... Confirmed 2026-07-18 that this meta-port does **not** pull in `thunar` (unlike most Linux Xfce metapackages) — `tools/make-iso.sh` fetches it as its own explicit package |
| Thunar | `thunar` (origin `x11-fm/thunar` family) | File manager; not a dependency of the `xfce` meta-port on FreeBSD, fetched explicitly |
| SDDM | `sddm` (origin `x11/sddm`, 0.21.0.36_3) | Display/login manager. Binary `/usr/local/bin/sddm`; ships `/usr/local/share/xsessions/xfce.desktop` (via `xfce4-session`) for the greeter to discover automatically |
| Xorg | `xorg-server` (origin `x11-servers/xorg-server`) | X server backing both the SDDM greeter and the Xfce session; not a separate runit service — SDDM spawns it itself |
| Xorg video driver | `xf86-video-scfb` (origin `x11-drivers/xf86-video-scfb`) + a forced `xorg.conf.d` snippet | Confirmed 2026-07-18, the hard way (live-tested boot: SDDM's own log showed X dying instantly, "Failed to read display number from pipe"): `xorg-server`'s dependency list (17 packages) pulls in `libdrm` but zero `xf86-video-*` driver packages — X.Org video drivers are always separate, never a server dependency. With `drm-kmod` deliberately deferred (see Open Questions), Xorg had no driver to load at all. `xf86-video-scfb` is FreeBSD's own hardware-independent syscons framebuffer driver, the standard unaccelerated fallback for generic hardware/VMs — exactly what this row's own "falls back to scfb/vesa" text already assumed. **Fetching the package alone was not enough**: re-tested after adding it, identical failure. Root cause: `scfb` is deliberately not PCI-ID-matched (it's the no-GPU-match fallback), so Xorg's PCI autoprobe never selects it on its own — confirmed by the failure being byte-for-byte identical before and after the package was added. `tools/make-iso.sh` now also writes `usr/local/etc/X11/xorg.conf.d/10-scfb.conf` forcing `Driver "scfb"` explicitly; this is the standard, platform-universal way to force an X.Org driver, not a FreeBSD-specific workaround. **Update 2026-07-21:** the baked snippet is renamed `10-video.conf` and is only the build-time default — `sunshine-provision-gpu` (src/sysaccounts/provision-gpu) rewrites it at every boot to `Driver "modesetting"` (xorg-server's built-in KMS DDX, glamor-accelerated) when a KMS GPU actually attached, keeping `scfb` as the fallback content otherwise |
| Xorg input driver | `xf86-input-libinput` (origin `x11-drivers/xf86-input-libinput`) | Confirmed 2026-07-18, the same class of gap as the video driver row above and found the same hard way: after fixing the framebuffer/UEFI/accounts issues, SDDM's greeter rendered correctly but the pointer never moved and no input registered at all — live-diagnosed via `top` (`sddm-greeter-qt6` at 0.00% CPU in `select`, Xorg also just sleeping): not a hang, both processes genuinely had nothing to receive. `xorg-server`'s dependency closure pulls zero `xf86-input-*` packages, same as it pulls zero video drivers. Unlike `xf86-video-scfb`, this needs no `xorg.conf.d` forcing — libinput isn't PCI-ID-matched either, but Xorg's input autoconfiguration picks up any available input driver for the keyboard/mouse device classes without help |
| Console framebuffer | `vesa_load="YES"` in `/boot/loader.conf` (base kernel module, no package) **+ UEFI boot required** | Confirmed 2026-07-18, the hard way, across two rounds: (1) adding `xf86-video-scfb` + forcing `Driver "scfb"` (row above) still hit "No devices detected" / "no screens found" on every live-tested boot; `kldload vesa` live, post-boot, provably had **zero effect** (identical manual `X` test before/after) since `vt(4)` picks its backend once at early boot attach, before userland runs — fixed by moving `vesa_load="YES"` into `loader.conf` so it loads before `vt(4)` probes. (2) Still failed identically even with that fix and `vesa.ko` confirmed loaded at boot (`kldstat`) — root cause was boot firmware mode, not the module: `xf86-video-scfb` only works when `vt(4)` has a real UEFI GOP framebuffer, which legacy BIOS boot never provides (confirmed against multiple independent FreeBSD forum reports, not just this project's own testing). The QEMU test command was booting legacy BIOS (`-boot d`, no firmware flags) the whole time; adding OVMF UEFI firmware (`-drive if=pflash,...edk2-x86_64-code.fd` + a writable vars pflash) fixed it immediately. `vesa_load="YES"` is left in `loader.conf` since it's harmless, but UEFI boot is the fix that actually mattered. Confirmed working end-to-end: X starts cleanly under UEFI, no more "no screens found" |
| SDDM greeter rendering | `sunshine-sddm` (src/sysaccounts/sddm-launch), the launcher every sddm path uses (`src/sunconfig/lib/registry.lua`'s service command and `src/flash/lib/start.lua`'s unsupervised launch): hardware GL when `/dev/dri/card*` exists, `QT_QUICK_BACKEND=software` fallback otherwise (2026-07-21; was an unconditional `QT_QUICK_BACKEND=software` before the DRM kmod landed) | Confirmed 2026-07-18: once Xorg itself started cleanly (row above), SDDM still produced only a black screen — X alive, VT/keyboard held, nothing painted, indistinguishable from a hang (confirmed: no amount of input reached the console until the QEMU instance was hard-reset). Root cause: SDDM's greeter is a Qt Quick (QML) application whose default scene graph wants a working OpenGL context, and this project has zero GPU acceleration on purpose right now (`xf86-video-scfb` is a plain unaccelerated framebuffer driver; `drm-kmod` is still deferred, see Open Questions below). `QT_QUICK_BACKEND=software` forces Qt Quick's software rasterizer instead. Not yet re-confirmed working end-to-end (requires a rebuild + reboot to test, same as the row above) |
| No-DM fallback | `xinit` (origin `x11/xinit`) + `startxfce4` (shipped by `xfce4-session`, already in the `xfce` meta-port) | Added 2026-07-18 in response to how painful the SDDM/Qt/GL debugging above was: `flash start xfce` bypasses SDDM entirely and execs `/usr/local/bin/startxfce4` directly — upstream's own tested no-display-manager launcher (runs `xinit` itself, picks a free VT, sources the right xfce `xinitrc`), not a hand-rolled `xinit`/`startx` invocation. Confirmed real 2026-07-18: `xinit` is **not** a transitive dependency of `xfce4-session` or the `xfce` meta-port (checked the live pkg repo, same class of gap as the `xf86-video-scfb` row above), so `tools/make-iso.sh` fetches it explicitly. Xfce/xfwm4 has no hard OpenGL requirement the way SDDM's QML greeter does (compositing is optional and degrades gracefully), so this path should work even before `drm-kmod` lands |
| D-Bus | `dbus` (origin `devel/dbus`) | System message bus; SDDM, polkit, and most of Xfce's session services depend on it being up first |
| polkit | `polkit` (origin `sysutils/polkit`) | Privilege escalation from inside an unprivileged Xfce session (mounting, power management, ...) |
| Seat backend | `consolekit2` (origin `sysutils/consolekit2`) | FreeBSD has no `systemd-logind`; polkit and Xfce expect *something* answering seat/session queries. `elogind` was tried first but does not exist as a FreeBSD package on any current branch — see "Seat backend: consolekit2" below |
| Service supervisor | `runit` (origin `sysutils/runit`, ships `/usr/local/etc/rc.d/runsvdir`) | Actually runs the `/service` tree `sunconfig` generates — see "runit bootstrap" below. Needs no dedicated system account |
| GPU accel | `drm-61-kmod` + the 14 `gpu-firmware-intel-kmod-*` packages (Intel only for now, user decision 2026-07-21) | Ships `i915kms.ko` + firmware; `sunshine-provision-gpu` detects an Intel display device via pciconf at boot, kldloads it, and flips Xorg to `modesetting` only when `/dev/dri/card*` actually appears — every failure degrades to the scfb/software path (see the rows above). Deliberately NOT the `drm-kmod` metaport, whose `gpu-firmware-kmod` dependency drags in ~180 AMD/Radeon firmware packages. GL userland was already present: `xorg-server`'s dependency closure pulls `mesa-dri`/`mesa-libs` (confirmed live 2026-07-21). The repo kmod is built against `__FreeBSD_version` 1404000 (14.4), so the ISO base was bumped 14.3 → 14.4-RELEASE the same day to match (verified live that the 14.4 disc1 ISO + checksum exist upstream); if the pairing ever skews again, the boot just continues on software rendering |
| Font | N/A — fetched directly from Google Fonts, not a FreeBSD port | Matches `PLAN.md`'s `Font: Open Sans` foundation decision. `tools/fetch-fonts.sh` pulls Open Sans (variable font, official google/fonts mirror) and Noto Color Emoji (emoji fallback, resolved live via the Fonts CSS2 API since its URL is versioned) into every ISO |

## Dependency / boot order

```
dbus (system bus)
  |
  +--> polkit (needs dbus)
  |
  +--> seat backend: consolekit2 (needs dbus; provides the seat/session
  |      state polkit consults)
  |
  v
sddm (needs dbus + polkit + seat backend + Xorg)
  |
  v
[user logs in via SDDM's PAM session]
  |
  v
xfce4-session (needs dbus + polkit for its own privileged actions)
```

Each of `dbus`, `polkit`, the seat backend, and `sddm` becomes its own
`/service/<name>/run` directory per `DOCS/RUNIT.MD`'s layout. `dbus` is
already anticipated as a service in `examples/etc-sunshine/services.lua`
(`dbus = { enabled = true, restart = true }`).

## SDDM as a native runit service

Per the retirement policy above, SDDM is never a `rc2runit` candidate —
it's a first-party default component and gets a native `run` script
like everything else in this plan. That's also simply the easier path
technically: SDDM doesn't double-fork when invoked directly — unlike
legacy `rc.d` daemons that assume `daemon(8)`-style backgrounding
(exactly what `rc2runit`'s polling wrapper exists to paper over for
*unported* third-party scripts), SDDM's own process model is already
"stay in the foreground, own the terminal," which is precisely runit's
`run`-script contract. This isn't a novel idea for a runit-based
system: Void Linux and Artix Linux, both runit-based distributions,
already supervise SDDM/LightDM/GDM exactly this way in production.
Void Linux in particular runs its own seat backend (`elogind`, on
Linux where it's packaged) as a runit-supervised service — the
precedent this plan follows for supervising the seat backend as a
native runit service too, not just for the display-manager supervision
model. The specific daemon differs on FreeBSD (`consolekit2`, see
below), but the "runit supervises it directly" shape is the same.

Illustrative sketch, not final (VT allocation and signal handling
still need working out — see Open Questions):

```sh
#!/bin/sh
# /service/sddm/run — supervised by runit, see DOCS/RUNIT.MD.
exec 2>&1
exec /usr/local/bin/sddm
```

One FreeBSD-specific wrinkle: without `systemd-logind`, SDDM can't get
DRM/GL device access the way it does on Linux. The documented
FreeBSD-native fix is simply putting the `sddm` user in the `video`
group, rather than relying on logind-style device handoff.

## Decisions

- **`sunshine_provision` must be ordered after `ldconfig`.** Confirmed
  live 2026-07-21 by capturing a full boot on the serial console:
  `provision-pkgfiles` builds its caches by running the packages' own
  tools out of `/usr/local/bin`, and every one of them is dynamically
  linked against `/usr/local/lib`. `etc/rc.d/ldconfig` is what adds
  that directory to the runtime linker's hints, and without it in the
  `REQUIRE:` line `rcorder` put provisioning at position 43 against
  `ldconfig`'s 45 — so every tool died at exec time (`ld-elf.so.1:
  Shared object "libglib-2.0.so.0" not found, required by
  "gdk-pixbuf-query-loaders"`), no caches were built, and the Xfce
  session aborted seconds after login with the same fatal libwnck
  assertion and SIGTRAP'd at-spi bus that `provision-pkgfiles` was
  written to prevent. Adding `ldconfig` moved it to 58 (after
  `ldconfig`), after which a login reached a stable, fully rendered
  Xfce desktop. **The general lesson is broader than this one script:
  anything in the rc(8) chain that executes a *port* binary has to
  REQUIRE `ldconfig`, the same way anything REQUIREing a port
  *service* has to live in `/usr/local/etc/rc.d` (see the rcorder
  two-pass note below).** It also hid for two days because the
  2026-07-19 verification ran the provisioning by hand from the
  installer's shell escape, where rc(8) — and so `ldconfig` — had
  already run; the real boot path was never exercised. `tests/
  test_iso_parts.sh` now generates the boot chain and asserts the
  ordering.

- **Desktop prerequisites copied from `sysutils/desktop-installer`.**
  2026-07-21, after reading the packaged script directly rather than
  guessing at what a FreeBSD desktop needs. Two things it does that
  this project did not: (1) `procfs_config()` — mount `procfs(5)` on
  `/proc` and add the `fstab` entry, done unconditionally for every
  desktop it supports, since nothing in FreeBSD's base mounts `/proc`
  but desktop software widely assumes it (now
  `src/sysaccounts/provision-procfs`); (2) `enable_user_shutdown()` —
  install a polkit rule authorizing `org.freedesktop.consolekit.
  system.restart`/`.stop` for the `operator` group, which is exactly
  what `x11-wm/xfce4-session`'s own pkg-message tells you to add by
  hand, and without which the log-out dialog's Shut Down / Restart
  buttons are inert. The build now ships that rule, `provision-
  accounts` puts `supser` in `operator`, and `provision-pkgfiles`
  restores `rules.d` to `polkitd:wheel 0700` (verified against
  polkit's real `+MANIFEST`) — polkit will not load rules from a
  directory it does not consider trustworthy, and plain extraction
  cannot preserve that mode.

- **Seat backend: consolekit2.** elogind was tried first —
  re-implementing systemd-logind's `org.freedesktop.login1` D-Bus API
  would have meant broader out-of-the-box compatibility with upstream
  desktop software that increasingly assumes that API rather than
  merely tolerating ConsoleKit2's older one. But checking the live
  FreeBSD pkg repos directly (`FreeBSD:13:amd64`, `:14:amd64`,
  `:15:amd64`) on 2026-07-18 found no `elogind` package on any of
  them — only `sysutils/consolekit2` and `sysutils/seatd` (a
  Wayland-compositor seat daemon, not a fit for SDDM+Xorg) exist.
  Shipping elogind would mean maintaining a new FreeBSD port from
  scratch, which is out of scope here. ConsoleKit2 is confirmed
  installable today (`sysutils/consolekit2` 2.0.0_1, daemon at
  `/usr/local/sbin/console-kit-daemon --no-daemon` to stay foreground
  for runit) and is what `src/sunconfig/lib/registry.lua` registers.

- **System accounts: `src/sysaccounts/provision-accounts`, not a
  patched `/etc/master.passwd`.** `tools/fetch-pkg.sh` is a plain
  archive extraction (see its header comment) — it never runs a
  fetched package's own pre-install script, so the dedicated system
  accounts `dbus` (`messagebus`, uid/gid 556), `polkit` (`polkitd`,
  uid/gid 565), and `sddm` (`sddm`, uid/gid 219, member of the base
  system's `video` group) never get created, and each daemon refuses to
  start without its account. Directly writing `/etc/master.passwd` at
  build time was considered and rejected: FreeBSD's `pw(8)`/
  `pwd_mkdb(8)` cannot execute on this Linux/WSL build host (wrong
  ABI), and hand-constructing the hashed `pwd.db`/`spwd.db` without
  them risks silent, unverifiable corruption. Instead,
  `provision-accounts` is a small idempotent script (tested against a
  faked `pw`, see `tests/test_provision_accounts.sh`) that runs `pw
  groupadd`/`useradd` for real, once per boot, on the real target
  system — see "runit bootstrap" below for how it's wired in.
- **Default interactive login account: `supser`, added to
  `provision-accounts`.** Confirmed live 2026-07-18: SDDM's own greeter
  actually rendered correctly (framebuffer, UEFI, accounts, and input
  driver fixes all landed) but showed an empty user carousel — nothing
  to select or log into. This is SDDM behaving correctly, not a bug:
  every mainstream display manager deliberately hides `root` from its
  picker by default. `provision-accounts` now also creates `supser`
  (uid/gid 1001, home `/home/supser`, shell `/bin/sh` — not `zsh`, which
  isn't fetched by this stage yet), a member of both `wheel` (admin
  access) and `video` (matching `sddm`'s own need for it), with a real,
  deliberately public, documented test password (`password`) set at
  creation via `pw useradd -h 0` (reads the password from stdin, the
  standard non-interactive `pw(8)` idiom). This is an openly-documented
  live/test default, the same way live-CD distros ship well-known
  default credentials — never meant to carry over to a real install as
  a security default. A real installer's own user-creation step (see
  the "custom ncurses+C installer" discussion, still future work)
  replaces this outright rather than building on it.
- **D-Bus machine-id: also generated by `provision-accounts`.** Confirmed
  live 2026-07-19: `flash start xfce`'s session failed downstream with a
  cascade of D-Bus/GLib/AT-SPI/ConsoleKit errors, all traced back to one
  root cause — `dbus-update-activation-environment` couldn't open either
  `/var/lib/dbus/machine-id` or `/etc/machine-id`, because neither was
  ever generated. Fetched and read the real `dbus` package's own rc.d
  script directly rather than guessing at the fix: its `start_precmd` does
  exactly `mkdir -p /var/lib/dbus; dbus-uuidgen --ensure` before
  `dbus-daemon` even starts. This project's runit service execs
  `dbus-daemon` directly (`registry.lua`), bypassing that rc.d script and
  its prestart hook entirely, so nothing else was ever going to run it.
  Added the identical two-step sequence to `provision-accounts` (not a new
  file — same "things fetch-pkg.sh's plain extraction never creates but
  real pkg install would have" charter this script already has), guarded
  by an overridable `DBUS_STATE_DIR` so tests never touch the real
  `/var/lib/dbus`. `dbus-uuidgen --ensure` is itself idempotent, matching
  the rest of this script's re-run safety.
- **`flash start ui`/`flash start xfce` now start `runsvdir` themselves
  when unsupervised, instead of leaving dbus/polkit/consolekit2 never
  running at all.** Even after the machine-id fix above, a real Xfce
  session (confirmed live 2026-07-19 — the furthest this project got all
  session: Xorg, xfce4-session, xfwm4, the panel, Thunar, xfdesktop, power
  manager, notifyd all actually launched) still logged a long tail of
  ConsoleKit-proxy and D-Bus-system-bus failures. Root cause: dbus, polkit,
  and consolekit2 are only ever started by runit supervising the
  `/service` tree, and runit is only ever started by `rc(8)` — which
  testing via the installer's live shell escape never runs at all (see
  DOCS/RUNIT.MD). `rc(8)` already does the right thing on a real boot;
  the fix is for the unsupervised path to do the same thing by hand.
  `src/flash/lib/start.lua`'s `plan()`/`plan_xfce()` now, when not
  supervised, background `/usr/local/sbin/runsvdir /service` (output
  redirected to `/var/log/sunshine-runsvdir.log`, confirmed real path via
  the live `runit` package) and then `exec` the real target (sddm or
  startxfce4) in the same shell invocation — `exec` means the process
  `deps.exec`'s caller ultimately waits on and reports the exit status of
  is still sddm/xfce itself, not the backgrounding step. This also starts
  sddm as a side effect for the `flash start xfce` path (it sits on its
  own, unused VT) — harmless, and not worth special-casing around, since
  runit supervises its whole tree indiscriminately by design.
- **`/service` needed the same read-only-root overlay treatment as
  `/etc`/`/home`/`/root`, discovered immediately after the fix above
  shipped.** Confirmed live 2026-07-19: starting `runsvdir` for real
  produced an endless respawn/zombie loop — every single `runsv <name>`
  died instantly with `fatal: unable to open supervise/lock: file does
  not exist`, for every enabled service. `runsv` creates its own
  `supervise/` runtime directory (`lock`, the `ok`/`control` FIFOs,
  `status`) the first time it starts supervising a service, and cannot
  on read-only media — the exact same class of bug, a fourth location.
  The `run`/`down` scripts `sunconfig build` already generated there are
  real, pre-existing content, so `/service` gets the same union-mount
  treatment as `/etc`/`/root`, not `/home`'s plain-empty one. Fixed in
  both places that matter: `tools/make-iso.sh`'s
  `sunshine_etc_overlay_start()` (the real `rc(8)` chain, so a genuine
  multi-user boot of the live ISO doesn't hit this either) and directly
  inside `src/flash/lib/start.lua`'s composed command — `plan()`/
  `plan_xfce()` now run the `/service` overlay call *synchronously*
  before backgrounding `runsvdir`, so `flash` needs no separate manual
  step for this at all, matching the user's explicit preference for
  self-sufficient fixes over more manual commands to remember.
- **`/etc` is read-only on this project's live/install ISO, and
  `provision-accounts` cannot run at all without `src/sysaccounts/
  etc-overlay` first.** Confirmed live 2026-07-18 the hard way: after
  finally getting SDDM's Xorg session to start (UEFI + `QT_QUICK_BACKEND`
  fixes above), the greeter still failed —
  `(WW) DAEMON: Failed to find the sddm user`, then `sddm-helper exited
  with 3 (HELPER_OTHER_ERROR)` — because `provision-accounts` had never
  successfully run. Running it by hand surfaced the real cause:
  `pw: gr_tmp(): Read-only file system`. Checked the ISO's own
  `/etc/fstab` directly: `/dev/iso9660/... / cd9660 ro` — root is
  mounted straight off the CD9660 image, genuinely read-only at the
  media level (this is stock FreeBSD `disc1.iso` behavior, not something
  this project's remastering broke). Baking real accounts into
  `/etc/master.passwd` at build time (rejected once already above, for a
  separate reason: `pw(8)`/`pwd_mkdb(8)` can't run on the Linux/WSL build
  host) would *also* not have helped here even if it worked, since it
  doesn't change anything about the live filesystem's writability for
  later runtime needs (sunconfig's own `/etc/sunshine` writes, etc).
  Chose a live, memory-backed unionfs overlay for `/etc` instead — the
  same category of fix stock FreeBSD already uses for `/var`/`/tmp`
  (`etc/rc.d/var`'s `varmfs="AUTO"`), confirmed by reading that actual
  script: it detects a read-only root via a failed `mkdir` probe and
  `mdmfs`'s a fresh filesystem directly over `/var` — safe there only
  because `/var`'s content is disposable (`mtree`-regenerated). `/etc`'s
  content is not disposable (passwd, group, rc.conf, fstab, every
  SunshineBSD file baked into the image), so `src/sysaccounts/etc-overlay`
  does the same failed-`mkdir`-probe detection but responds with a real
  unionfs mount instead of a replace-mount: `mdmfs` a fresh, empty,
  writable filesystem at a scratch mountpoint, then `mount -t unionfs`
  it *over* `/etc` — reads of anything not yet written fall through to
  the original read-only `/etc` automatically, writes land in the new
  upper layer, no pre-copying needed. Wired into the boot chain as
  `etc/rc.d/sunshine_etc_overlay` (`REQUIRE: var`, `BEFORE:
  sunshine_provision`) — see "runit bootstrap" below and DOCS/RUNIT.MD.
  Also directly invokable by hand (`/usr/local/sbin/sunshine-etc-overlay`)
  for the same installer-shell-escape testing gap `provision-accounts`
  itself has. Re-confirmed necessary in two more places, same script,
  different `$TARGET`/`$UPPER`: `/home` (confirmed live 2026-07-19 — it
  does not exist at all in the stock tree, not even empty, so
  `supser`'s homedir creation failed outright; `tools/make-iso.sh` now
  bakes an empty `/home` directory into `$dist_stage` at build time so
  there is something to mount onto — no pre-existing content to
  preserve there, unlike `/etc`, but the same union-mount code path
  handles an empty lower layer fine) and `/root` (confirmed live
  2026-07-19 — `flash start xfce`'s own X session failed to write
  `.serverauth.NNNN`/`.Xauthority` into root's home directory, which is
  real base-system content, so this one gets the same preserving
  treatment `/etc` does). `etc/rc.d/sunshine_etc_overlay` now calls
  `sunshine-etc-overlay` three times, once per target.
- **Runit bootstrap: `runit`'s own `rc.d/runsvdir`, plus one
  SunshineBSD-written `rc.d/sunshine_provision`.** A gap discovered
  2026-07-18 while implementing this stage: nothing had ever actually
  started runit. `sunconfig build` generates a `/service` tree, but
  the `runit` package itself (`runsvdir`/`runsv`/`sv`/`svlogd`) was
  never fetched, and Stage 4 (replacing `rc(8)` with runit as PID 1's
  child) is explicitly future work, not this stage's. The pragmatic
  fix, confirmed against the real `runit` FreeBSD package: it already
  ships `/usr/local/etc/rc.d/runsvdir` (default
  `runsvdir_path=/var/service`, repointed to `/service` via an
  `/etc/rc.conf.d/runsvdir` drop-in — see below). `tools/make-iso.sh`
  writes one additional rc.d script, `etc/rc.d/sunshine_provision`
  (`BEFORE: runsvdir`), whose only job is running
  `provision-accounts` before runit starts supervising anything that
  needs those accounts. This is deliberately the *smallest* possible
  stopgap — one rc.d entry-point, not a parallel service system — and
  is meant to be deleted outright once Stage 4 replaces `rc(8)` for
  real.
- **dbus/polkit/consolekit2 moved off runit entirely, onto plain
  `rc(8)`, per explicit user direction 2026-07-19.** After multiple
  rounds this session of chasing runit-bootstrap fragility (missing
  machine-id, missing `/service` overlay, needing `flash` to bootstrap
  `runsvdir` from a shell escape that never runs `rc(8)` at all), the
  call was made to stop routing these three specifically through runit:
  they are foundational, always-on prerequisites that don't need
  runit's per-session flexibility (start once at boot, stay up), and
  bootstrapping them through runit meant *also* bootstrapping runsvdir
  itself whenever `rc(8)` hadn't run — real, avoidable fragility for
  services that never needed it. `sddm` (and anything else declared in
  `examples/etc-sunshine/services.lua`) stays on runit; only these
  three moved.
  `dbus` uses its own real upstream rc.d script (just enabled via
  `dbus_enable="YES"`) — its `start_precmd` already does the
  `mkdir -p /var/lib/dbus; dbus-uuidgen --ensure` dance correctly, so
  the duplicate of that logic added to `provision-accounts` earlier this
  session was removed as redundant. `polkit` and `consolekit2` ship no
  rc.d script upstream at all (confirmed live by fetching both packages
  directly) — `tools/make-iso.sh` now writes one for each, wrapping the
  foreground-only daemons (`polkitd --no-debug`, `console-kit-daemon
  --no-daemon` — neither backgrounds itself) via `daemon(8)`, the exact
  pattern `x11/sddm`'s own real rc.d script already uses. Verified
  `daemon(8)`'s `-p pidfile` semantics against the actual manual page
  before relying on it (forks the wrapped program into a tracked
  background child and returns immediately) rather than assuming, since
  getting this wrong would hang the entire sequential `rc(8)` boot.
  Ordering: `sunshine_provision` gained `BEFORE: dbus` (accounts must
  exist before dbus-daemon setuid's to `messagebus`); `polkit` and
  `consolekit2` each declare `REQUIRE: dbus` and `BEFORE: runsvdir` —
  transitively this places all three, in order, ahead of `runsvdir`
  without needing to edit dbus's or runit's own upstream rc.d files at
  all.
  Removed from `src/sunconfig/lib/registry.lua` (no longer a runit
  service catalog entry) and `examples/etc-sunshine/services.lua`.
  `src/flash/lib/start.lua`'s runsvdir-bootstrap comments/descriptions
  updated to stop claiming it brings up dbus/polkit/consolekit2 — it no
  longer does, and testing via the installer's live shell escape (which
  skips `rc(8)` entirely) now simply won't have them running, an
  accepted characteristic rather than a gap for `flash` to paper over.
  A real multi-user boot is the only way to test with them running.
- **rc.conf changes: per-service `/etc/rc.conf.d/<name>` drop-ins, never
  a direct edit to `/etc/rc.conf`.** Confirmed 2026-07-18 against the
  live ISO's own `/etc/rc.subr` (`load_rc_config` sources
  `${_d}/rc.conf.d/"$_name"` when present) and against the live ISO's
  actual `/etc/rc.conf` (non-empty: `sendmail_enable`, `hostid_enable`
  already set). `tools/make-iso.sh` builds every SunshineBSD addition
  once into `$dist_stage`, then fans it out onto both the live ISO tree
  (`cp -Rp`) and `sunshine.txz`; a shared `etc/rc.conf` built in
  `$dist_stage` would have silently clobbered whichever real
  `etc/rc.conf` it landed on in either destination. Drop-in files never
  collide.
- **`sunshine.txz` ownership: `bsdtar --uid 0 --gid 0` at pack time.**
  Also discovered while implementing this stage: `$dist_stage` is built
  by whichever unprivileged user runs `tools/make-iso.sh`, and `bsdtar`
  preserves on-disk ownership by default when creating an archive — so
  every file in `sunshine.txz`, not just this stage's additions, was
  being recorded as owned by the build host's numeric uid/gid rather
  than root. A real `bsdinstall` extraction would have left all of
  SunshineBSD's files non-root-owned. Fixed by forcing
  `--uid 0 --uname root --gid 0 --gname root` at archive-creation time
  (confirmed real, documented `bsdtar` 3.8.4 flags).
- **`sunconfig`'s `fs.exists`/`fs.is_dir` fixed for read-only media.**
  Live-tested boot (the motd's own suggested `sunconfig check`): a
  populated, correct `/etc/sunshine` (confirmed via `ls -la`) was
  reported as "not a directory". Root cause, confirmed via a live
  `flua` one-liner on the booted system: `fs.lua` tested existence with
  `os.rename(path, path)` (a no-op self-rename only succeeds if the
  path exists) — but the install/live medium mounts its root
  **read-only**, so every rename failed with EROFS regardless of
  whether the path existed. Fixed by switching to pure reads
  (`io.open`), verified live on the same booted system before shipping
  the fix (not just assumed to carry over from Linux/WSL testing,
  which had masked the bug since dev filesystems there are writable).
  Windows needed its own carve-out in the same fix — confirmed
  separately that Windows `fopen()` refuses to open directories at all
  and does not fail the POSIX way for a file with `/.` appended, the
  mirror-image problem from the same root cause (an OS-behavior
  assumption baked into a generic check). See `DOCS/ENGINEERING.MD`
  rule 3.9 for the general lesson. `flash`'s `path_exists` (added for
  the FIFO-safety problem below) still uses the rename-based check
  deliberately for `supervise/ok` specifically — that one really is a
  FIFO, where a read-based check would block forever.
  **The flagged-but-unconfirmed risk this created did turn out real,
  confirmed live 2026-07-19**: `flash enable dbus` reported
  "no such service: /service/dbus" even though it was genuinely baked
  into the image at ISO-build time (`tools/make-iso.sh` already calls
  `sunconfig build -o "$dist_stage/service"` for real) — `src/flash/lib/
  cli.lua`'s `enable` handler was using the same rename-based
  `deps.path_exists` for *all three* checks (`dir`, `dir/down`,
  `dir/supervise/ok`), and `/service` sits on the same read-only cd9660
  root as everything else, so `os.rename` failed with EROFS regardless
  of whether the path existed — reporting every baked-in service as
  missing. Fixed by using `deps.exists` (pure read, read-only-media-safe)
  for the `dir`/`dir/down` checks, keeping `deps.path_exists` only for
  the actual FIFO (`supervise/ok`). `flash start`'s own use of
  `path_exists` was already correct (it only ever checks `supervise/ok`,
  never a plain dir/file), so that path needed no change.
- **"SDDM runs, Xfce doesn't": root-caused end to end by automated live
  debugging, 2026-07-19.** The 0.3.1-BETA ISO was booted headless in
  QEMU (serial console + monitor-driven keyboard/screenshots), the
  greeter login reproduced, and the session's own log
  (`~supser/.local/share/sddm/xorg-session.log`) captured: the Xfce
  session genuinely *started* (xfce4-session, xfwm4, panel, Thunar,
  xfdesktop all launched) and then collapsed within ~30 seconds. Five
  distinct real bugs, every one fixed after being confirmed on the
  booted system — including confirming the fix itself live (caches
  regenerated in-guest + a fresh login produced a stable, fully
  rendered Xfce desktop):
  1. **Missing pkg-generated caches killed the session (the actual
     killer).** `GLib-GIO-ERROR: No GSettings schemas are installed` is
     a FATAL abort (SIGTRAP — also the endless `org.a11y.Bus received
     signal 5`), and the missing gdk-pixbuf `loaders.cache` ("Could not
     load a pixbuf from icon theme") ended in a fatal libwnck
     assertion that took the session down. These files
     (`gschemas.compiled`, `loaders.cache`, mime database, per-theme
     `icon-theme.cache`) are built by pkg post-install scripts, which
     `tools/fetch-pkg.sh`'s plain extraction never runs. Fixed by the
     new `src/sysaccounts/provision-pkgfiles` (run from
     `sunshine_provision` at boot and by `flash start`'s unsupervised
     path), which builds each cache with the package's own tool,
     idempotently, mounting its own `/usr/local` overlay on read-only
     media.
  2. **polkit/consolekit2 never ran: `/etc/rc` two-pass rcorder bug.**
     Both rc.d scripts lived in `etc/rc.d` but `REQUIRE: dbus`, which
     lives in `usr/local/etc/rc.d`. Pass 1 orders base `etc/rc.d`
     alone; `rcorder` reported ``requirement `dbus' has no providers``
     and sorted `polkit` to position 1 of the entire boot (verified
     with `rcorder` on the live system) — both daemons started before
     dbus existed, died, were marked done, and pass 2 never retried
     them. Both scripts now install to `usr/local/etc/rc.d`, where only
     pass 2 (base + local together, dbus visible) ever orders them.
     Starting both by hand on the live system worked immediately,
     confirming the scripts themselves were fine.
  3. **Every runit log service crash-looped, and full pipes wedged
     services.** `/var/log/sunshine/<name>` never exists at runtime
     (`/var` is a fresh mdmfs each live boot; make-iso only copies the
     `service/` subtree anyway), so every `svlogd` died instantly and
     each main service wrote to a pipe with no reader — which BLOCKS
     the writer once full (one service sat wedged for 4000+ seconds on
     a single error line, observed live). Generated `log/run` scripts
     now `mkdir -p` their own log directory first.
  4. **`/service/desktop` was a pre-SDDM leftover exec'ing lightdm** —
     never installed, crash-looping every boot (`gen_runit`'s
     `desktop.environment=xfce -> /usr/local/sbin/lightdm` mapping).
     Removed: the DM is `sddm`, a normal `services.lua` service.
  5. **D-Bus system-bus activation was broken: `+MANIFEST` permissions
     lost.** `dbus-daemon-launch-helper` must be `04750
     root:messagebus` (and `pkexec`/`polkit-agent-helper-1` `04755`) —
     read directly from the real package manifests — but bsdtar
     extracting as an unprivileged Linux build user cannot apply
     those, leaving `rwxr-x--- root:wheel` and every activation failing
     with "Failed to execute program ...: Permission denied" (the
     ConsoleKit/UPower errors in the session log).
     `provision-pkgfiles` restores them at boot. `upower` itself is
     now also fetched (real package, `sysutils/upower`, confirmed
     against the live index) so xfce4-power-manager has its backend.
  Plus one latent build bug found during the same audit:
  `tools/fetch-pkg.sh`'s `echo | while` pipeline orphaned the final
  partial batch of background fetch jobs (a subshell's children are
  invisible to the parent's `wait`), so ISO packing could race still-
  running extractions. The loop now reads from a temp file in the
  parent shell.

## Open Questions

- **VT switching / getty coordination.** This is a distinct wrinkle
  from the rc(8) retirement policy above, not an exception to it:
  FreeBSD's `init(8)` (PID 1, not replaceable within this roadmap)
  spawns `getty` per `/etc/ttys` entry directly — a lower-level
  facility that predates and is independent of `rc.d`/`/etc/rc`
  entirely. "Runit does everything" still applies to it, though: the
  Void Linux pattern is to set every `/etc/ttys`-equivalent entry to
  not-respawning and let runit supervise `getty` itself, one
  `/service/agetty-ttyv<N>/run` per virtual terminal, so `init(8)`'s
  own responsibility shrinks to "start runit" and nothing else. That's
  the intended direction here too — the vty SDDM claims gets its
  `/etc/ttys` entry set to `off` and a runit-supervised `getty` service
  (or none, since SDDM itself owns that vty) rather than being left to
  `init(8)`. Full "every vty is a runit service" isn't built yet;
  tracked here so it isn't lost, not resolved by this document.
- **GPU acceleration default.** ~~Whether `drm-kmod` ships enabled by
  default vs. opt-in/autodetected is deferred to Stage 1's hardware
  detection work — not decided in this document.~~ Decided 2026-07-21:
  autodetected at boot, Intel only for now. `sunshine-provision-gpu`
  probes pciconf, kldloads `i915kms`, and picks `modesetting` vs `scfb`
  per boot; `sunshine-sddm` picks the greeter's Qt Quick backend the
  same way. Software rendering remains the automatic fallback whenever
  the hardware path fails for any reason. AMD/NVIDIA remain open.
- **Eventual `sunconfig` integration.** Once Stage 8 is further along,
  `desktop = { environment = "xfce", ... }` in `examples/etc-sunshine/
  desktop.lua` should be what generates this runit service tree,
  the same way `services.lua` already anticipates declaring `dbus`.
  Until then, these services are installed and wired up directly
  (`tools/make-iso.sh` or a new `tools/make-desktop.sh`), the same
  pattern `flesk` and `sunconfig` follow today.

## Staged Plan

- **Stage D0/D1 — dbus + polkit + consolekit2 done, scripted directly.**
  2026-07-18: rather than a manual VM proof-of-concept first, `dbus`,
  `polkit`, and `consolekit2` (plus their full transitive pkg
  dependency closure — 32 packages fetched straight from the live
  FreeBSD pkg repo) were wired directly into `tools/make-iso.sh`, via
  the new `tools/fetch-pkg.sh` (resolution logic in `src/pkgfetch/`,
  tested) and `tools/fetch-fonts.sh` (Open Sans + Noto Color Emoji).
  `sunconfig build` also now runs at ISO-build time and bakes the
  generated `/service` tree (including `dbus`/`polkit`/`consolekit2`)
  onto every ISO. **Not done yet:** `xfce4`, `sddm`, `xorg` — those
  still need this same treatment before there's a working boot-to-
  desktop path.
- **Stage D0/D1 remaining — XFCE + SDDM + Xorg.** Same treatment as
  above: install via `tools/fetch-pkg.sh`, add `sddm`/`xfce4-session`
  runit services, reach a working XFCE desktop via SDDM login on a
  rebuilt ISO.
- **Stage D2 — Branding pass.** SunshineBSD SDDM theme (sunflower
  branding, Open Sans, the golden color scheme already established for
  the boot loader in `branding/loader/gfx-sunshine.lua`), Xfce
  panel/theme defaults.
- **Stage D3 — `sunconfig` integration.** `desktop.lua` becomes the
  real source of truth per `DOCS/LUA.MD`'s pipeline, generating the
  runit service tree instead of hand-maintained scripts.

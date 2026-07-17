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

| Component | Typical port | Role |
|-----------|---------------|------|
| XFCE | x11-wm/xfce4 (meta) | Desktop environment: `xfce4-session`, `xfce4-panel`, `xfwm4`, `thunar`, `xfce4-appfinder`, ... |
| SDDM | x11/sddm | Display/login manager |
| Xorg | x11-servers/xorg-server (or x11/xorg meta) | X server backing both the SDDM greeter and the Xfce session |
| D-Bus | devel/dbus | System message bus; SDDM, polkit, and most of Xfce's session services depend on it being up first |
| polkit | sysutils/polkit | Privilege escalation from inside an unprivileged Xfce session (mounting, power management, ...) |
| Seat backend | sysutils/consolekit2 | FreeBSD has no `systemd-logind`; polkit and Xfce expect *something* answering seat/session queries. `elogind` was tried first but does not exist as a FreeBSD package on any current branch — see "Seat backend: consolekit2" below |
| GPU accel | graphics/drm-kmod | Kernel modesetting for Intel/AMD; without it, Xorg falls back to `scfb`/`vesa` (functional, unaccelerated) |
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
- **GPU acceleration default.** Whether `drm-kmod` ships enabled by
  default vs. opt-in/autodetected is deferred to Stage 1's hardware
  detection work — not decided in this document.
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

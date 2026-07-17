# SunshineBSD Development Plan

SunshineBSD is an opinionated desktop-focused BSD operating system built on
the FreeBSD kernel.

> Keep FreeBSD's proven foundation. Replace components gradually.
> Build a secure, atomic, opinionated desktop OS on top.

Goals:

- Maintain BSD philosophy and licensing freedom
- Provide a modern desktop experience
- Prioritize security and rollback capability
- Give users freedom while restricting applications

Core Principles:

- Atomic updates
- Snapshot-based recovery
- Capability-based security
- Simple configuration
- User-first desktop experience

Foundation decisions:

```
Kernel:     FreeBSD
Filesystem: ZFS
Desktop:    XFCE
Shell:      zsh
Font:       Open Sans
```

---

## Stage 0 — FreeBSD Base Fork

**Goal:** Create a stable SunshineBSD foundation.

- Fork FreeBSD source tree (see `tools/fetch-freebsd.sh`; the upstream tree
  is vendored under `vendor/freebsd-src`, never committed here).
- Establish SunshineBSD branding (`branding/`).
- Create build infrastructure.
- Define supported hardware.
- Maintain compatibility with FreeBSD drivers.

## Stage 1 — Modern User Experience Layer

**Goal:** Make FreeBSD feel like a desktop OS.

- XFCE default environment, Open Sans system font, modern themes.
- Hardware detection and a GUI installer.
- Default accounts: one user account plus `root`.
- Avoid unnecessary enterprise features.

## Stage 2 — Storage Foundation

**Goal:** Make system recovery first-class. ZFS is mandatory.

- Root filesystem on ZFS.
- Automatic snapshots and boot environments.
- Rollback support (`sunshine@pre-update` → `sunshine@current`).

## Stage 3 — Mandatory Swap Policy

**Goal:** Protect system stability.

- 2 GiB minimum swap, created automatically during installation.
- Cannot be removed; user may increase; system warns before reducing.
- Rationale: memory-pressure protection, crash prevention, ZFS workload
  safety, better recovery behavior.

## Stage 4 — Replace rc(8) with runit

**Goal:** Simplify service management. See `DOCS/RUNIT.MD`.

- Services live in `/service/<name>/run` under runit supervision.
- Fast boot, automatic restart, simple debugging, small codebase.
- `rc-compat` (`src/rc-compat/rc2runit`) wraps legacy rc.d scripts during
  the transition.

## Stage 5 — Package Ecosystem

**Goal:** Modern package management (`sunpkg`, based on pkg + apk concepts).

- Atomic package transactions with pre-transaction ZFS snapshots.
- Signed packages, rollback support.

## Stage 6 — Linux Compatibility Layer

**Goal:** Access the Linux ecosystem without becoming Linux (`BSD2Linux`).

- Run Alpine packages, Linux binaries, selected Linux applications.
- No libc replacement, no musl migration. Compatibility, not conversion.

## Stage 7 — FUSE Integration

**Goal:** Modern filesystem features.

- User filesystem mounting, sandboxed filesystem views, virtual paths
  (`fakepath://photo.png` instead of real home-directory paths).

## Stage 8 — Lua Configuration System

**Goal:** Replace scattered configuration. See `DOCS/LUA.MD`.

- `/etc/sunshine/*.lua` (or a single `sun.conf.lua`) describes the system.
- The `sunconfig` compiler (`src/sunconfig/`) validates it and generates
  native configuration: `/etc/*`, `/service/*`.
- Changes are transactional: ZFS snapshot before apply, rollback on failure.

## Stage 9 — Atomic Update System

**Goal:** Never modify the running OS.

- Updates install into a new ZFS boot environment; reboot activates it.
- On failure the boot menu offers the previous version.

## Stage 10 — KerrNil Security Layer

**Goal:** Mandatory application security. KerrNil is the final authority
between applications and the kernel.

- Applications run sandboxed; root applications are still restricted.
- Permissions are capability-based; real paths hidden behind `fakepath://`.

## Stage 11 — KerrNil Configuration

- Chosen once at installation time (`allow root override?`); the choice
  cannot be changed later. After setup, `root ≠ unlimited power`.
- KerrNil comes **last** — it is the most invasive component and must not
  be built while the rest of the OS is still unstable.

---

## Final Architecture

```
                 Applications
                      |
                  KerrNil
                      |
                  Userland
                      |
                 FreeBSD Kernel
                      |
                    ZFS
```

## Release Roadmap

| Release | Contents                                          |
|---------|---------------------------------------------------|
| 0.1     | FreeBSD fork, XFCE, zsh, ZFS, Open Sans           |
| 0.5     | runit, atomic updates, snapshots, new package system |
| 0.8     | BSD2Linux, FUSE integration, Lua configuration    |
| 1.0     | KerrNil security layer, full atomic desktop OS    |

The BSD-like evolution rule: **replace one component, stabilize, replace
the next.**

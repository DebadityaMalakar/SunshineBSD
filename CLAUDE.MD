The philosophy would be:

> **Keep FreeBSD's proven foundation. Replace components gradually. Build a secure, atomic, opinionated desktop OS on top.**

Something like:

```md
# SunshineBSD Development Plan

SunshineBSD is an opinionated desktop-focused BSD operating system built on
the FreeBSD kernel.

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
```

---

# Stage 0 — FreeBSD Base Fork

**Goal:** Create a stable SunshineBSD foundation.

Tasks:

* Fork FreeBSD source tree.
* Establish SunshineBSD branding.
* Create build infrastructure.
* Define supported hardware.
* Maintain compatibility with FreeBSD drivers.

Decisions:

```
Kernel: FreeBSD
Filesystem: ZFS
Desktop: XFCE
Shell: zsh
Font: Open Sans
```

---

# Stage 1 — Modern User Experience Layer

**Goal:** Make FreeBSD feel like a desktop OS.

## Default Desktop

Implement:

* XFCE default environment.
* Open Sans system font.
* Modern themes.
* Hardware detection.
* GUI installer.

Defaults:

```
User:
    <username>

Administrator:
    root
```

Avoid unnecessary enterprise features.

---

# Stage 2 — Storage Foundation

**Goal:** Make system recovery first-class.

## ZFS Mandatory

SunshineBSD uses ZFS by default.

Features:

* Root filesystem on ZFS.
* Automatic snapshots.
* Boot environments.
* Rollback support.

Example:

```
Before update:

sunshine@pre-update

Update:

sunshine@current

Failure:

Rollback → sunshine@pre-update
```

---

# Stage 3 — Mandatory Swap Policy

**Goal:** Protect system stability.

Default:

```
Swap:
2 GiB minimum
```

Rules:

* Created automatically during installation.
* Cannot be removed.
* User may increase size.
* System warns before reducing.

Reason:

* Memory pressure protection.
* Crash prevention.
* ZFS workload safety.
* Better recovery behavior.

Example:

```
RAM:
8GB

Swap:
2GB

RAM:
128GB

Swap:
2GB
```

---

# Stage 4 — Replace rc(8) with runit

**Goal:** Simplify service management.

Replace:

```
FreeBSD rc.d
```

with:

```
runit supervision
```

Architecture:

```
/etc/service/

    sshd/
       run

    network/
       run

    desktop/
       run
```

Benefits:

* Fast boot.
* Automatic service restart.
* Simple debugging.
* Small codebase.

Compatibility:

Create:

```
rc-compat
```

during transition.

---

# Stage 5 — Package Ecosystem

**Goal:** Provide modern package management.

## Sunshine Package Manager

Based on:

* pkg
* apk concepts

Features:

* Atomic package transactions.
* Signed packages.
* Rollback support.

Example:

```
sunpkg install firefox

Transaction created.

Snapshot:
sunshine@before-firefox

Installing...

Success.
```

---

# Stage 6 — Linux Compatibility Layer

**Goal:** Access Linux ecosystem without becoming Linux.

Implement:

```
BSD2Linux
```

Purpose:

Run:

* Alpine packages.
* Linux binaries.
* Selected Linux applications.

Architecture:

```
Linux Application

        ↓

BSD2Linux Layer

        ↓

FreeBSD Kernel
```

No libc replacement.

No musl migration.

Compatibility, not conversion.

---

# Stage 7 — FUSE Integration

**Goal:** Enable modern filesystem features.

Support:

* User filesystem mounting.
* Sandboxed filesystem views.
* Virtual paths.

Example:

```
fakepath://photo.png
```

instead of:

```
/home/user/private/photos/photo.png
```

---

# Stage 8 — Lua Configuration System

**Goal:** Replace scattered configuration.

Introduce:

```
sun.conf.lua
```

Example:

```lua
system = {
    hostname = "sunshine",
    timezone = "Asia/Kolkata"
}

services = {
    ssh = false,
    bluetooth = true
}

desktop = {
    environment = "xfce"
}
```

Compiler generates:

```
/etc/*
/service/*
```

---

# Stage 9 — Atomic Update System

**Goal:** Never modify the running OS.

Update flow:

```
User works normally

        ↓

Update downloaded

        ↓

New ZFS environment created

        ↓

Packages installed there

        ↓

Reboot

        ↓

New environment activated
```

Failure:

```
Boot menu:

SunshineBSD Previous Version
SunshineBSD Current Version
```

---

# Stage 10 — KerrNil Security Layer

**Goal:** Introduce mandatory application security.

KerrNil becomes the final security authority.

Architecture:

```
Applications

      ↓

KerrNil

      ↓

Kernel
```

Rules:

* Applications run sandboxed.
* Root applications are still restricted.
* Permissions are capability-based.

Example:

Application:

```
Request:
Open image
```

KerrNil:

```
Allowed.

Actions:
✓ Copy image
✓ Remove EXIF
✓ Hide real path

Return:
fakepath://image.png
```

---

# Stage 11 — KerrNil Configuration

During installation:

```
KerrNil Security Setup

[✓] Protect applications

Allow root override?

[ ] No

WARNING:
This choice cannot be changed later.
```

After setup:

```
root ≠ unlimited power
```

---

# Final SunshineBSD Architecture

```
                 Applications
                      |
                      |
                  KerrNil
                      |
                      |
                  Userland
                      |
                      |
                 FreeBSD Kernel
                      |
                      |
                    ZFS
```

---

# Release Roadmap

## SunshineBSD 0.1

* FreeBSD fork
* XFCE
* zsh
* ZFS
* Open Sans

## SunshineBSD 0.5

* runit
* atomic updates
* snapshots
* new package system

## SunshineBSD 0.8

* BSD2Linux
* FUSE integration
* Lua configuration

## SunshineBSD 1.0

* KerrNil security layer
* Full atomic desktop OS

---

The main thing I'd emphasize is **KerrNil comes last**. Not because it's the least important, but because it's the most invasive. If you build it too early, you end up debugging your security layer while also debugging the OS itself. 😭

This roadmap gives SunshineBSD a very BSD-like evolution: replace one component, stabilize, replace the next. That's how you avoid creating a beautiful but impossible-to-maintain monster. 🗿

Also READ:

- DOCS/LUA.MD
- DOCS/RUNIT.MD
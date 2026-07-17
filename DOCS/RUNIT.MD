
## `DOCS/RUNIT.md`

```md
# SunshineBSD Runit Service System

## Overview

SunshineBSD replaces FreeBSD rc.d service management with runit.

The goal is a simpler, faster, and more reliable service supervision system.

## Philosophy

A service should be:

- Easy to start
- Easy to stop
- Easy to inspect
- Automatically supervised

A service failure should recover automatically.

## Architecture

Traditional FreeBSD:

````

rc.d scripts

```
 |
 v
```

Service startup

```

SunshineBSD:

```

runit

|
+-- service directory
|
+-- run script
|
+-- supervision

```

---

# Service Layout

Services exist under:

```

/service/

```

Example:

```

/service/
sshd/
run
log/

```
network/
    run

desktop/
    run
```

```

---

# Service Definition

Example:

```

/service/example/run

````

```sh
#!/bin/sh

exec /usr/local/bin/example-server
````

The service remains active while the process exists.

---

# Service States

A service can be:

```
enabled
disabled
failed
restarting
```

---

# Service Management

Commands:

Start:

```
sv up sshd
```

Stop:

```
sv down sshd
```

Restart:

```
sv restart sshd
```

Status:

```
sv status sshd
```

---

# Boot Process

SunshineBSD boot:

```
Kernel

  |
  v

init

  |
  v

runit

  |
  v

system services

  |
  v

desktop environment
```

---

# rc.d Compatibility

During migration SunshineBSD provides:

```
rc-compat
```

Purpose:

Allow existing FreeBSD services to run.

Migration:

```
rc.d script

      |
      v

runit service generator

      |
      v

/service/example/run
```

---

# Integration With Lua

Services are controlled through Lua.

Example:

```lua
services = {

    sshd = {
        enabled = true,
        restart = true
    },

    bluetooth = {
        enabled = false
    }

}
```

The Lua compiler generates runit services.

---

# Atomic Updates

Runit integrates with SunshineBSD atomic updates.

Before updating:

```
Snapshot:

zroot@before-update
```

Update services.

Reboot.

If failure:

```
Rollback system snapshot
```

---

# Future Integration

Runit will integrate with:

* SunshineBSD installer
* Lua configuration
* Atomic updates
* KerrNil security layer

Future:

```
Application

    |
    v

KerrNil sandbox

    |
    v

runit supervision

    |
    v

kernel


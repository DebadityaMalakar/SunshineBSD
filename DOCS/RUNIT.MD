# SunshineBSD Runit Service System

## Overview

SunshineBSD replaces FreeBSD rc.d service management with runit.

The goal is a simpler, faster, and more reliable service supervision
system.

## Philosophy

A service should be:

- Easy to start
- Easy to stop
- Easy to inspect
- Automatically supervised

A service failure should recover automatically.

## Architecture

Traditional FreeBSD:

```
rc.d scripts
      |
      v
Service startup (one-shot, unsupervised)
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

## Service Layout

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
            run
    network/
        run
    desktop/
        run
```

A `down` file in a service directory marks it disabled. A `finish`
script controls restart behavior.

## Service Definition

A service is a directory containing an executable `run` script:

```
/service/example/run
```

```sh
#!/bin/sh
exec 2>&1
exec /usr/local/bin/example-server
```

The service remains active while the process exists.

## Service States

A service can be:

```
enabled
disabled
failed
restarting
```

## Service Management

```
sv up sshd         start
sv down sshd       stop
sv restart sshd    restart
sv status sshd     status
```

## Boot Process

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

## rc.d Compatibility

During migration SunshineBSD provides `rc-compat`, implemented as
`src/rc-compat/rc2runit`. It allows existing FreeBSD rc.d services to
run under supervision:

```
rc.d script
      |
      v
rc2runit generator
      |
      v
/service/example/run
```

The generated wrapper calls the rc.d script's `onestart`, traps TERM to
run `onestop`, and polls `onestatus` so runit sees a live process.

## Integration With Lua

Services are declared in Lua configuration (see DOCS/LUA.MD):

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

The `sunconfig` compiler generates the runit service tree: `run`
scripts, `log/run` scripts using svlogd, `down` files for disabled
services, and `finish` scripts where `restart = false`.

## Atomic Updates

Runit integrates with SunshineBSD atomic updates (see DOCS/ZFS.MD).
Before updating, `sunsnap pre update` creates a safety point; the
update happens in a new boot environment; a failed update is undone by
activating the previous environment and rebooting.

## Future Integration

Runit will integrate with:

- The SunshineBSD installer
- Lua configuration
- Atomic updates
- The KerrNil security layer

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
```

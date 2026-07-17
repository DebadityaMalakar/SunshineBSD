## `DOCS/LUA.md`

# SunshineBSD Lua Configuration System

## Overview

SunshineBSD uses Lua as its primary system configuration language.

The goal is to provide a unified, readable, and programmable configuration
layer without replacing the underlying Unix filesystem model.

Lua is not intended to replace system binaries or become a mandatory runtime
dependency for applications. It exists as a configuration and orchestration
language.

## Philosophy

Traditional Unix systems distribute configuration across many files:

- /etc/rc.conf
- /etc/fstab
- /etc/sysctl.conf
- service configuration files
- package configuration files

SunshineBSD introduces a unified configuration layer:

    Lua Configuration
          |
          v
    Configuration Generator
          |
          v
    Native Unix Configuration

The generated files remain readable and editable.

## Goals

- Human-readable configuration
- Programmable configuration
- Easy automation
- Reproducible system setup
- No custom DSL
- Minimal complexity

## Non Goals

Lua configuration will not:

- Replace shell scripting entirely
- Replace package management
- Become a programming environment for applications
- Hide the underlying system

## Configuration Layout

Example:

```

/etc/sunshine/
system.lua
services.lua
desktop.lua
security.lua

````

## Example Configuration

### System

```lua
system = {
    hostname = "sunshine",
    timezone = "Asia/Kolkata",
    locale = "en_US.UTF-8"
}
````

Generated:

```
/etc/rc.conf
/etc/localtime
```

---

## Services

Example:

```lua
services = {
    ssh = true,
    bluetooth = false,
    network = true
}
```

The service manager converts this into runit service definitions.

---

## Desktop

Example:

```lua
desktop = {
    environment = "xfce",
    font = "Open Sans",
    terminal = "zsh"
}
```

---

# Configuration Compiler

The configuration compiler is responsible for:

1. Loading Lua configuration
2. Validating values
3. Generating system configuration
4. Applying changes safely

Pipeline:

```
sun.lua

    |
    v

sunconfig

    |
    v

/etc
/service
/boot
```

---

# Safety

Configuration changes are transactional.

Before applying:

```
Create ZFS snapshot

zroot@suncfg-before
```

Apply configuration.

If failure occurs:

```
Rollback snapshot
```

---

# Future Integration

Lua will eventually control:

* Package preferences
* Atomic update policies
* KerrNil security policies
* User permissions
* Hardware profiles

Example future:

```lua
security = {
    kernil = true,
    allow_root_override = false
}
```

---

# Summary

Lua is the configuration language of SunshineBSD.

It provides:

* Simplicity of traditional Unix
* Power of scripting
* Safety of declarative configuration

Configuration should describe the system,
not fight the user.


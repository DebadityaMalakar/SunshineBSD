# SunshineBSD Lua Configuration System

## Overview

SunshineBSD uses Lua as its primary system configuration language.

The goal is to provide a unified, readable, and programmable
configuration layer without replacing the underlying Unix filesystem
model.

Lua is not intended to replace system binaries or become a mandatory
runtime dependency for applications. It exists as a configuration and
orchestration language.

## Philosophy

Traditional Unix systems distribute configuration across many files:

- /etc/rc.conf
- /etc/fstab
- /etc/sysctl.conf
- service configuration files
- package configuration files

SunshineBSD introduces a unified configuration layer:

```
Lua Configuration
      |
      v
Configuration Generator
      |
      v
Native Unix Configuration
```

The generated files remain readable and editable.

## Goals

- Human-readable configuration
- Programmable configuration
- Easy automation
- Reproducible system setup
- No custom DSL
- Minimal complexity

## Non-Goals

Lua configuration will not:

- Replace shell scripting entirely
- Replace package management
- Become a programming environment for applications
- Hide the underlying system

## Configuration Layout

Configuration lives in `/etc/sunshine/`, either as a single
`sun.conf.lua` or split across topical files:

```
/etc/sunshine/
    system.lua
    services.lua
    desktop.lua
    security.lua
```

## Example Configuration

### System

```lua
system = {
    hostname = "sunshine",
    timezone = "Asia/Kolkata",
    locale = "en_US.UTF-8"
}
```

Generated:

```
/etc/rc.conf
/etc/localtime
```

### Services

```lua
services = {
    ssh = true,
    bluetooth = false,
    network = true
}
```

The generator converts this into runit service definitions
(see DOCS/RUNIT.MD).

### Desktop

```lua
desktop = {
    environment = "xfce",
    font = "Open Sans",
    terminal = "zsh"
}
```

## Configuration Compiler

The configuration compiler, `sunconfig` (implemented in
`src/sunconfig/`), is responsible for:

1. Loading Lua configuration inside a sandbox
2. Validating values, collecting every error in one pass
3. Generating system configuration into a staging tree
4. Applying changes safely

Pipeline:

```
/etc/sunshine/*.lua
      |
      v
   sunconfig
      |
      v
/etc  /service  /boot
```

## Safety

Configuration changes are transactional.

Before applying:

```
sunsnap pre config
```

creates a ZFS safety point (see DOCS/ZFS.MD). Apply the generated
configuration. If a failure occurs, roll back to the safety point.

Untrusted configuration is evaluated only inside a sandbox: no `io`,
no `os`, no `require`, no bytecode, bounded instruction count
(DOCS/ENGINEERING.MD, rule 3.8).

## Future Integration

Lua will eventually control:

- Package preferences
- Atomic update policies
- KerrNil security policies
- User permissions
- Hardware profiles

Example future configuration:

```lua
security = {
    kernil = true,
    allow_root_override = false
}
```

## Summary

Lua is the configuration language of SunshineBSD.

It provides:

- The simplicity of traditional Unix
- The power of scripting
- The safety of declarative configuration

Configuration should describe the system, not fight the user.

# New-WSLSymbolicLink

Creates a single symlink inside a WSL distribution (`ln -s`) at `Path` pointing to `Target`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
New-WSLSymbolicLink -Path "/home/user/.ssh/config" -Target "/mnt/c/Users/User/.ssh/config" -Distribution "Ubuntu"
```

## Related

- [`New-WSLSymbolicLink` in the System module reference](../../../modules/system.md#new-wslsymboliclink) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

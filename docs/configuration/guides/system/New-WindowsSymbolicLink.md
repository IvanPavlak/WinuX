# New-WindowsSymbolicLink

Creates a single native Windows symbolic link at `Path` pointing to `Target`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
New-WindowsSymbolicLink -Path "$env:USERPROFILE\.gitconfig" -Target "C:\Repo\Git\.gitconfig"
```

## Related

- [`New-WindowsSymbolicLink` in the System module reference](../../../modules/system.md#new-windowssymboliclink) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

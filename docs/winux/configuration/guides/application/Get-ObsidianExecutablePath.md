# Get-ObsidianExecutablePath

Resolves `Obsidian.exe` for a detached launch: beside the CLI, then in `%LOCALAPPDATA%\Programs\obsidian`, then from the `obsidian://` protocol handler registered under `HKCU:\Software\Classes\obsidian`. Returns `$null` when no candidate exists.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ObsidianExecutablePath
```

Used by `Start-ObsidianDetached`, which needs the executable because a process created through WMI cannot be started from a URI alone.

## Related

- [`Get-ObsidianExecutablePath` in the Application module reference](../../../modules/application.md#get-obsidianexecutablepath) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

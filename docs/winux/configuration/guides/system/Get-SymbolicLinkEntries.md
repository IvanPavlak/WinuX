# Get-SymbolicLinkEntries

Flattens a (possibly nested) `SymbolicLinks` configuration hashtable into a flat list of link entry objects, optionally filtered by `-Scope` and `-Name`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-SymbolicLinkEntries -SymbolicLinks $MachineSpecificPaths.SymbolicLinks -Scope WSL
```

## Related

- [`Get-SymbolicLinkEntries` in the System module reference](../../../modules/system.md#get-symboliclinkentries) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

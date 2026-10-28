# Update-DirectoryNames

Scans directories under a given path for names ending in a date suffix (`YYYY_MM_DD`) and renames them so the date becomes today's date.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Update-DirectoryNames
Update-DirectoryNames -Path "C:\My Folders"
Update-DirectoryNames -Path "C:\My Folders" -WhatIf
```

## Related

- [`Update-DirectoryNames` in the System module reference](../../../modules/system.md#update-directorynames) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

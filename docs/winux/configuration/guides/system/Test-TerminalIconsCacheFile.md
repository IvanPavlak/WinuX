# Test-TerminalIconsCacheFile

Reports whether one `Terminal-Icons` theme cache file parses as Clixml, never throwing; `Repair-TerminalIconsThemeCache` runs it on every cache file to find the torn ones.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-TerminalIconsCacheFile -Path "$env:APPDATA\powershell\Community\Terminal-Icons\prefs.xml"
$reason = $null; Test-TerminalIconsCacheFile -Path $file -Reason ([ref]$reason)
```

## Related

- [`Test-TerminalIconsCacheFile` in the System module reference](../../../modules/system.md#test-terminaliconscachefile) - parameters, usage and behaviour
- [`Repair-TerminalIconsThemeCache`](Repair-TerminalIconsThemeCache.md) - moves aside the files it reports as unreadable
- [System configuration guides](README.md) - every guide for this module

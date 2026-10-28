# Import-TerminalIcons

Imports `Terminal-Icons` into the global session state (the file and folder glyphs in directory listings) and, when the import fails on a torn theme cache file, moves that file aside with `Repair-TerminalIconsThemeCache` and imports again, up to three attempts in all. The profile queues it as the startup stage `Terminal-Icons`, run after the first prompt.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

The module's theme cache lives outside the repository, at `%APPDATA%\powershell\Community\Terminal-Icons\`. To start one shell without the import, set `$env:WINUX_STARTUP_SKIP = "Terminal-Icons"` before `pwsh`.

## Usage

```powershell
Import-TerminalIcons
Import-TerminalIcons -RedrawPrompt
```

## Related

- [`Import-TerminalIcons` in the System module reference](../../../modules/system.md#import-terminalicons) - parameters, usage and behaviour
- [`Repair-TerminalIconsThemeCache`](Repair-TerminalIconsThemeCache.md) - the cache repair it runs on a failed import
- [`Restore-ShellPrompt`](../helper/Restore-ShellPrompt.md) - what `-RedrawPrompt` calls
- [Directory Listings Print Without Icons](../../../reference/troubleshooting.md#directory-listings-print-without-icons) - the symptom and the fix by hand
- [System configuration guides](README.md) - every guide for this module

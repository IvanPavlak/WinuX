# Repair-TerminalIconsThemeCache

Moves aside every `Terminal-Icons` theme cache file that no longer parses - renamed to `<name>.corrupt-<timestamp>` beside the original, never deleted - so the module can import again and regenerate the file from its built-in themes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

The cache lives outside the repository, at `%APPDATA%\powershell\Community\Terminal-Icons\` (`-Path` points it at another folder, for example a copy).

## Usage

```powershell
Repair-TerminalIconsThemeCache
Repair-TerminalIconsThemeCache -Path "D:\Backup\Terminal-Icons"
```

## Related

- [`Repair-TerminalIconsThemeCache` in the System module reference](../../../modules/system.md#repair-terminaliconsthemecache) - parameters, usage and behaviour
- [`Import-TerminalIcons`](Import-TerminalIcons.md) - runs it when the import fails
- [Directory Listings Print Without Icons](../../../reference/troubleshooting.md#directory-listings-print-without-icons) - the symptom and the fix by hand
- [System configuration guides](README.md) - every guide for this module

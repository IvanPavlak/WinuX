# Format-ZoneContent

Formats an array of content items (process names, window titles) to fit within a specified character width.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Format-ZoneContent -Content @("ProcessName", "WindowTitle") -Width 16
```

## Related

- [`Format-ZoneContent` in the Window module reference](../../../modules/window.md#format-zonecontent) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

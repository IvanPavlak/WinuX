# Get-WindowDesktopIndex

Resolves which virtual desktop a window lives on, as a 0-based index, returning `-1` for every "cannot tell" case rather than `$null` or an exception.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WindowDesktopIndex -WindowHandle $window.Handle
```

## Related

- [`Get-WindowDesktopIndex` in the Window module reference](../../../modules/window.md#get-windowdesktopindex) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

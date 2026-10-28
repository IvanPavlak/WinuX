# Get-WindowHandle

Retrieves window handles (HWND) for windows belonging to the specified process name or window title pattern.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WindowHandle -ProcessName "chrome"
Get-WindowHandle -ProcessName "(firefox|chrome|msedge|brave)"
Get-WindowHandle -WindowTitle "*YouTube*"
```

## Related

- [`Get-WindowHandle` in the Window module reference](../../../modules/window.md#get-windowhandle) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

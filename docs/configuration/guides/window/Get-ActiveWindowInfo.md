# Get-ActiveWindowInfo

Retrieves detailed information about all open windows (or a filtered subset) and writes it to `ActiveWindowInfo.txt` on the desktop, including process name, window title, handle, position, size, and a ready-to-use config template for each window.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ActiveWindowInfo
Get-ActiveWindowInfo -Window "*Firefox*"
Get-ActiveWindowInfo -Window "(.*Calendar.*|.*Week.*)"
```

## Related

- [`Get-ActiveWindowInfo` in the Window module reference](../../../modules/window.md#get-activewindowinfo) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

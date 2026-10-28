# Wait-WindowRect

Polls a window's rectangle (via the native `GetWindowRect` API) until it matches expected bounds within a tolerance, or a time budget elapses.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440
Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440 -TimeoutMs 500
```

## Related

- [`Wait-WindowRect` in the Window module reference](../../../modules/window.md#wait-windowrect) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

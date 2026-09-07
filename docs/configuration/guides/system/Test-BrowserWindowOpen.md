# Test-BrowserWindowOpen

Tells whether a window handle still refers to a live, visible window (`IsWindow` and `IsWindowVisible`) - the liveness probe `Wait-BrowserWindowsClosed` polls.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-BrowserWindowOpen -Handle $window.Handle
```

## Related

- [`Test-BrowserWindowOpen` in the System module reference](../../../modules/system.md#testbrowserwindowopen) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

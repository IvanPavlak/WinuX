# Wait-BrowserWindowsClosed

Waits for browser windows that were sent `WM_CLOSE` to actually disappear and returns the ones still standing when the timeout expires, so `Terminate-AllBrowserProcesses` can retry or report them.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$survivors = Wait-BrowserWindowsClosed -Windows $windowsToClose
Wait-BrowserWindowsClosed -Windows $survivors -TimeoutMs 2000
```

## Related

- [`Wait-BrowserWindowsClosed` in the System module reference](../../../modules/system.md#waitbrowserwindowsclosed) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

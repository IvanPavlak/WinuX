# Wait-WindowsClosed

Polls the live window list until every window handed to it has gone, or a timeout expires, and returns the ones still open.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-WindowsClosed -Window $postedWindows
Wait-WindowsClosed -Window $postedWindows -TimeoutMilliseconds 3000
```

## Related

- [`Wait-WindowsClosed` in the Window module reference](../../../modules/window.md#wait-windowsclosed) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

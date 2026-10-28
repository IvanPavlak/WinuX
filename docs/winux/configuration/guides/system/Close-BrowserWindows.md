# Close-BrowserWindows

Gracefully closes previously discovered browser windows by posting `WM_CLOSE` directly to each supplied native window handle.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Close-BrowserWindows -WindowsToClose $windows
```

## Related

- [`Close-BrowserWindows` in the System module reference](../../../modules/system.md#close-browserwindows) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

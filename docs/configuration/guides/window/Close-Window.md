# Close-Window

Asks a window to close by posting `WM_CLOSE` to its handle - the one graceful-close seam in the repository.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Close-Window -Handle $window.Handle
```

## Related

- [`Close-Window` in the Window module reference](../../../modules/window.md#close-window) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

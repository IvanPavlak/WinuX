# Set-StackedWindowOrder

Stacks the windows of several layout entries that share one zone in layout file order, so the window of the last entry ends on top on every run.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$null = Set-StackedWindowOrder -Results $layoutResults
```

## Related

- [`Set-StackedWindowOrder` in the Window module reference](../../../modules/window.md#set-stackedwindoworder) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

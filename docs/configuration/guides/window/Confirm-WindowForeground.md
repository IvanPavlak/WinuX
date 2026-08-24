# Confirm-WindowForeground

Acquires and verifies stable foreground focus for a window.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Confirm-WindowForeground -WindowHandle $handle
Confirm-WindowForeground -WindowHandle $handle -BaseSettleMs 10 -MaxAttempts 3
```

## Related

- [`Confirm-WindowForeground` in the Window module reference](../../../modules/window.md#confirm-windowforeground) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

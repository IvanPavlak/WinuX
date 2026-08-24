# Reset-KeyboardModifiers

Releases modifier keys (Shift, Ctrl, Alt, Win - left, right, and neutral variants) that the session reports as logically held down, by injecting the matching key-up events in a single `SendInput` batch.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Reset-KeyboardModifiers
Reset-KeyboardModifiers -IncludeMouseButton
```

## Related

- [`Reset-KeyboardModifiers` in the Window module reference](../../../modules/window.md#reset-keyboardmodifiers) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

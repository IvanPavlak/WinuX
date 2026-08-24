# Add-PositionedWindow

Adds a window handle to the positioned windows tracking set.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Add-PositionedWindow -WindowHandle $window.Handle -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "MyApp" -DesktopNumber 0
```

## Related

- [`Add-PositionedWindow` in the Window module reference](../../../modules/window.md#add-positionedwindow) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

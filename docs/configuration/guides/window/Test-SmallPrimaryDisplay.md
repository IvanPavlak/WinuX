# Test-SmallPrimaryDisplay

Tests whether the display that is currently primary is laptop-class - at most `MaxWidthPx` wide (3000px by default), which puts 1920x1080 and 2560x1440 panels in and a 3440x1440 ultrawide or a 4K desktop monitor out.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-SmallPrimaryDisplay
Test-SmallPrimaryDisplay -MonitorInfo $cachedMonitorInfo
Test-SmallPrimaryDisplay -MaxWidthPx 2000
```

## Related

- [`Test-SmallPrimaryDisplay` in the Window module reference](../../../modules/window.md#test-smallprimarydisplay) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

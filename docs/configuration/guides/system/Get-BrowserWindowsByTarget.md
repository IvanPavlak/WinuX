# Get-BrowserWindowsByTarget

Enumerates visible top-level windows (via the native `Win32BrowserHelper` type) for the supplied browser process IDs and returns only the ones whose titles match the provided regex.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern "Google Chrome"
```

## Related

- [`Get-BrowserWindowsByTarget` in the System module reference](../../../modules/system.md#get-browserwindowsbytarget) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

# Get-BrowserWindowsByTarget

Reads the Window module's window enumeration and returns every visible, titled window owned by the supplied browser process IDs, flagging the ones whose title matches the brand pattern.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern "Google Chrome"
```

## Related

- [`Get-BrowserWindowsByTarget` in the System module reference](../../../modules/system.md#get-browserwindowsbytarget) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

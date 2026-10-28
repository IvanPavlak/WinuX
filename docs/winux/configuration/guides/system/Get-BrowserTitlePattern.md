# Get-BrowserTitlePattern

Returns the window title regex that identifies a browser's main windows, from a built-in map keyed by the browser names `Configuration.Universal.Browsers` uses (Firefox, Tor, Chrome, Edge, Brave); unknown names return `$null`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-BrowserTitlePattern -BrowserName "Edge"
```

## Related

- [`Get-BrowserTitlePattern` in the System module reference](../../../modules/system.md#get-browsertitlepattern) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

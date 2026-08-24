# Collect-BrowserUrls

Recursively collects all URLs from nested browser group hashtables, flattening the hierarchical `BrowserGroups` structure (from `Configuration.psd1`) into a flat URL array.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Collect-BrowserUrls -Value $Configuration.BrowserGroups.GroupName
```

## Related

- [`Collect-BrowserUrls` in the Helper module reference](../../../modules/helper.md#collect-browserurls) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

# Close-BrowserTabsByPattern

Helper that closes all browser tabs whose titles match one or more regex patterns.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger")
Close-BrowserTabsByPattern -ProcessName "msedge" -TitlePatterns @("(?i)localhost:5000")
```

## Related

- [`Close-BrowserTabsByPattern` in the Workflow module reference](../../../modules/workflow.md#close-browsertabsbypattern) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module

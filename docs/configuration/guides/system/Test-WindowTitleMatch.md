# Test-WindowTitleMatch

Tests whether a window/process matches any of the provided patterns, returning a boolean.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-WindowTitleMatch -WindowTitle "YouTube - Google Chrome" -Patterns @("*YouTube*")
Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1 - Visual Studio Code" -Patterns @("Code")
Test-WindowTitleMatch -WindowTitle "Gmail Inbox" -Patterns @("(.*Gmail.*|.*Inbox.*)")
```

## Related

- [`Test-WindowTitleMatch` in the System module reference](../../../modules/system.md#test-windowtitlematch) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

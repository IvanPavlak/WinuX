# Test-WindowTitleCandidates

Tests a window title against a list of candidate strings using case-insensitive, regex-escaped matching, returning `$true` on the first match.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-WindowTitleCandidates -WindowTitle "MyProject - Visual Studio Code" -Candidates @("MyProject", "MyRepo")
```

## Related

- [`Test-WindowTitleCandidates` in the Helper module reference](../../../modules/helper.md#test-windowtitlecandidates) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

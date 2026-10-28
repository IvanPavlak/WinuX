# Test-WindowTitleCandidates

Tests a window title against a list of candidate strings, returning `$true` when any candidate is a whole ` - ` separated title segment (case-insensitive, matched literally).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-WindowTitleCandidates -WindowTitle "MyProject - Visual Studio Code" -Candidates @("MyProject", "MyRepo")
Test-WindowTitleCandidates -WindowTitle "MySolution (Debugging) - Microsoft Visual Studio" -Candidates @("MySolution") -ProcessName "devenv"
```

## Related

- [`Test-WindowTitleCandidates` in the Helper module reference](../../../modules/helper.md#test-windowtitlecandidates) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

# Write-ManualInstructionsToDesktop

Writes formatted manual setup instructions to a text file on the user's Desktop, with a title, an underline separator, the body content, and a generated timestamp.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-ManualInstructionsToDesktop -FileName "setup-instructions.txt" -Title "MyProject Setup" -Content "1. Do this...
```

## Related

- [`Write-ManualInstructionsToDesktop` in the Helper module reference](../../../modules/helper.md#write-manualinstructionstodesktop) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

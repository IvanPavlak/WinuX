# Get-VSCodeExecutablePath

Resolves `Code.exe` (one folder above `code.cmd`, then the per-user and machine-wide installs) for `Start-VSCodeDetached`, or `$null` when VS Code is not installed.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VSCodeExecutablePath
```

## Related

- [`Get-VSCodeExecutablePath` in the Application module reference](../../../modules/application.md#get-vscodeexecutablepath)
- [Application configuration guides](README.md)

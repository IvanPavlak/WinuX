# Get-PwshPath

Returns a `pwsh.exe` path that keeps working after PowerShell updates, for the MSI and the MSIX install alike.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-PwshPath
Get-PwshPath -PowerShellHome 'C:\Program Files\PowerShell\7'
```

## Related

- [`Get-PwshPath` in the Helper module reference](../../../modules/helper.md#get-pwshpath) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

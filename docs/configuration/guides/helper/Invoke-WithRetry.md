# Invoke-WithRetry

Executes a script block with exponential backoff retry logic, attempting it up to `-MaxAttempts` times.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-WithRetry -ScriptBlock { Invoke-RestMethod -Uri $url } -MaxAttempts 5
Invoke-WithRetry -ScriptBlock { Get-DesktopList } -OnRetry { param($ErrorRecord, $Attempt) Reset-VirtualDesktopState }
```

## Related

- [`Invoke-WithRetry` in the Helper module reference](../../../modules/helper.md#invoke-withretry) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

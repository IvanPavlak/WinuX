# Invoke-WithOptionalRetry

Executes a script block with optional retry/backoff behavior.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-WithOptionalRetry -ScriptBlock { Get-DesktopList }
Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -MaxAttempts 3 -InitialDelayMs 200
Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -OnRetry { param($ErrorRecord, $Attempt) Reset-VirtualDesktopState }
```

## Related

- [`Invoke-WithOptionalRetry` in the Helper module reference](../../../modules/helper.md#invoke-withoptionalretry) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

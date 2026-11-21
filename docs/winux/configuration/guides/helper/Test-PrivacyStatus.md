# Test-PrivacyStatus

Performs comprehensive privacy verification for VPN connections with optional Tor support.

> [!WARNING]
> **Deprecated since 2.17.0, removed in 3.0.0.** `Test-PrivacyStatus` serves one personal setup rather than the framework. To keep it, copy the function file (and its test) into your fork's Custom area under `Windows/PowerShell/Modules/Custom/<Module>/Functions/`, list it in `Custom.psd1`, and keep its keys in `Configuration.local.psd1`, where the copy goes on reading them. The function keeps working until 3.0.0 and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-PrivacyStatus
Test-PrivacyStatus -UseTor
Test-PrivacyStatus -Silent
```

## Related

- [`Test-PrivacyStatus` in the Helper module reference](../../../modules/helper.md#test-privacystatus) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

# Invoke-PrivacyRequest

Helper that makes an HTTP request either directly via `Invoke-RestMethod` or, when `-UseTor` is specified, through the Tor SOCKS5 proxy via `Invoke-TorRequest`.

> [!WARNING]
> **Deprecated since 2.17.0, removed in 3.0.0.** `Invoke-PrivacyRequest` serves one personal setup rather than the framework. To keep it, copy the function file (and its test) into your fork's Custom area under `Windows/PowerShell/Modules/Custom/<Module>/Functions/`, list it in `Custom.psd1`, and keep its keys in `Configuration.local.psd1`, where the copy goes on reading them. The function keeps working until 3.0.0 and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-PrivacyRequest -Uri "https://api.ipify.org?format=json"
Invoke-PrivacyRequest -Uri "https://check.torproject.org/api/ip" -UseTor
```

## Related

- [`Invoke-PrivacyRequest` in the Helper module reference](../../../modules/helper.md#invoke-privacyrequest) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

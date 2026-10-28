# Invoke-PrivacyRequest

Helper that makes an HTTP request either directly via `Invoke-RestMethod` or, when `-UseTor` is specified, through the Tor SOCKS5 proxy via `Invoke-TorRequest`.

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

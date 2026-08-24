# Invoke-TorRequest

Makes an HTTP request through Tor for anonymity.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-TorRequest -Uri "https://check.torproject.org/api/ip"
Invoke-TorRequest -Uri "https://api.example.com/data" -TimeoutSec 30 -RetryCount 3
```

## Related

- [`Invoke-TorRequest` in the Helper module reference](../../../modules/helper.md#invoke-torrequest) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

# Get-DotnetVersionFromTFM

Parses a .NET Target Framework Moniker (TFM) such as `net8.0`, `netcoreapp3.1`, `net48`, or `netstandard2.0` and extracts version information.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-DotnetVersionFromTFM -TFM "net8.0"
Get-DotnetVersionFromTFM -TFM "netcoreapp3.1"
Get-DotnetVersionFromTFM -TFM "net48"
```

## Related

- [`Get-DotnetVersionFromTFM` in the Helper module reference](../../../modules/helper.md#get-dotnetversionfromtfm) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

# ConvertFrom-UpstreamManifest

Parses an upstream manifest or a fork's `Git/upstreams.local.conf` into an object.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ConvertFrom-UpstreamManifest -Text (Get-Content -Raw Windows\PowerShell\Upstream.conf)
```

## Related

- [`ConvertFrom-UpstreamManifest` in the Git module reference](../../../modules/git.md#convertfrom-upstreammanifest) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

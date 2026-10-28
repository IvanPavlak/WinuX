# Resolve-UpstreamPathClass

Decides what a merge from one upstream does with one path: take it, or put it back.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-UpstreamPathClass -Path 'README.md' -Upstream $winux -Others @($foundation) -RootOwner 'fork'
```

## Related

- [`Resolve-UpstreamPathClass` in the Git module reference](../../../modules/git.md#resolve-upstreampathclass) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

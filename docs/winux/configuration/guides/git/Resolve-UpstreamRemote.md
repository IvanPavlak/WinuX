# Resolve-UpstreamRemote

Finds the git remote of an upstream by its manifest URL, or says which command adds it.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-UpstreamRemote -Name 'winux' -Url 'https://github.com/IvanPavlak/WinuX.git' -Remotes @{ upstream = 'https://github.com/IvanPavlak/WinuX.git' }
```

## Related

- [`Resolve-UpstreamRemote` in the Git module reference](../../../modules/git.md#resolve-upstreamremote) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

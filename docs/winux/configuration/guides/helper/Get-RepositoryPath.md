# Get-RepositoryPath

Resolves the repository's key directories without hardcoding folder depth.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
(Get-RepositoryPath).Modules
Get-RepositoryPath -StartPath $PSScriptRoot
```

## Related

- [`Get-RepositoryPath` in the Helper module reference](../../../modules/helper.md#get-repositorypath) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

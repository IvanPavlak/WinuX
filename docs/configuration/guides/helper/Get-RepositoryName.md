# Get-RepositoryName

Extracts the repository name from a Git URL.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-RepositoryName -RepositoryUrl "https://github.com/user/MyRepo.git"
Get-RepositoryName -RepositoryUrl "git@github.com:user/MyRepo.git"
```

## Related

- [`Get-RepositoryName` in the Helper module reference](../../../modules/helper.md#get-repositoryname) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

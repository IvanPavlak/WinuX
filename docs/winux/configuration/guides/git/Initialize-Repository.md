# Initialize-Repository

Clones a repository to a local path, or, if it already exists there, updates it with [`Update-Repository`](Update-Repository.md), which keeps local work safe.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"
Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo" -Token $pat
```

## Related

- [`Initialize-Repository` in the Git module reference](../../../modules/git.md#initialize-repository) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

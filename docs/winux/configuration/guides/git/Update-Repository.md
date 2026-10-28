# Update-Repository

Updates one cloned repository - the checked-out branch, optionally the default branch - with local changes stashed before and restored after, and returns the result.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. Whether it fast-forwards the default branch is the `-IncludeDefaultBranch` switch its caller passes, which [`Update-Repositories`](Update-Repositories.md) takes from [`RepositoryUpdate.IncludeDefaultBranch`](../../configuration-reference.md#repository-update); the branch name comes from [`Resolve-RepositoryDefaultBranch`](Resolve-RepositoryDefaultBranch.md).

## Usage

```powershell
Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo"
Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -IncludeDefaultBranch -Quiet | Format-List
```

## Related

- [`Update-Repository` in the Git module reference](../../../modules/git.md#update-repository) - parameters, usage and behaviour
- [`Update-Repositories`](Update-Repositories.md) - the caller, and where the configuration is read
- [`Update-RepositoryDefaultBranch`](Update-RepositoryDefaultBranch.md) - the default-branch step
- [Git configuration guides](README.md) - every guide for this module

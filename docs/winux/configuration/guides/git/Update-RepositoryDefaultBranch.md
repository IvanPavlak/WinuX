# Update-RepositoryDefaultBranch

Fast-forwards a repository's default branch without checking it out, with `git fetch origin <default>:<default>`, which git refuses unless it is a fast-forward and which never touches the working tree or the stash.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The branch name it is handed comes from [`Resolve-RepositoryDefaultBranch`](Resolve-RepositoryDefaultBranch.md), and whether `Update-Repositories` calls it at all is [`RepositoryUpdate.IncludeDefaultBranch`](../../configuration-reference.md#repository-update), configured through [`Update-Repositories`](Update-Repositories.md).

## Usage

```powershell
Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login
Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login -LocalPath "<DevRoot>\MyRepo" -Quiet
```

## Related

- [`Update-RepositoryDefaultBranch` in the Git module reference](../../../modules/git.md#update-repositorydefaultbranch) - parameters, usage and behaviour
- [`Resolve-RepositoryDefaultBranch`](Resolve-RepositoryDefaultBranch.md) - names the branch
- [`Update-Repositories`](Update-Repositories.md) - the caller
- [Git configuration guides](README.md) - every guide for this module

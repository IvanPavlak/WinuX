# Restore-RepositoryStash

Gives back exactly one stash, identified by its commit, restoring staged changes as staged, and drops it only once it is fully restored.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It is the restore step of [`Update-Repository`](Update-Repository.md).

## Usage

```powershell
$stash = git rev-parse refs/stash
Restore-RepositoryStash -StashCommit $stash
```

## Related

- [`Restore-RepositoryStash` in the Git module reference](../../../modules/git.md#restore-repositorystash) - parameters, usage and behaviour
- [`Update-Repository`](Update-Repository.md) - the caller
- [Git configuration guides](README.md) - every guide for this module

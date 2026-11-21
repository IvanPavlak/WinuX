# GitBranchDeleteAndPrune

Deletes local branches with `git branch -d` and prunes stale remote-tracking refs for origin. A branch git refuses (not fully merged, squash-merged) is offered once for a force delete; `-Force` forces straight away. Without `-BranchName` it offers the local branches in a menu that takes one or more; Enter deletes nothing. Alias: `gbd`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
GitBranchDeleteAndPrune feature/done
GitBranchDeleteAndPrune -BranchName "feature/a", "feature/b"
gbd feature/abandoned -Force
gbd    # pick one or more branches from a menu
```

## Related

- [`GitBranchDeleteAndPrune` in the Git module reference](../../../modules/git.md#gitbranchdeleteandprune) - parameters, usage and behaviour
- [GitWorktreeRemoveAndPrune](GitWorktreeRemoveAndPrune.md) - removes worktrees and hands their branches to this function
- [Git configuration guides](README.md) - every guide for this module

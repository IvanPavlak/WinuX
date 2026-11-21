# GitWorktreeRemoveAndPrune

Prunes stale worktree entries, removes linked worktrees with `git worktree remove` (`-Force` adds `--force`), and offers to delete their branches through `GitBranchDeleteAndPrune` (Yes, No or Force; Enter means No). Without `-Worktree` it offers the linked worktrees in a menu that takes one or more; the main, the current and locked worktrees are never offered, and Enter removes nothing. Alias: `gwd`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
GitWorktreeRemoveAndPrune feature/done
GitWorktreeRemoveAndPrune -Worktree "..\MyRepo-hotfix"
gwd feature/a, feature/b -Force
gwd    # pick one or more worktrees from a menu
```

## Related

- [`GitWorktreeRemoveAndPrune` in the Git module reference](../../../modules/git.md#gitworktreeremoveandprune) - parameters, usage and behaviour
- [GitBranchDeleteAndPrune](GitBranchDeleteAndPrune.md) - deletes the branches it hands over
- [Git configuration guides](README.md) - every guide for this module

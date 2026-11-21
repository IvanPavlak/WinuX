# GitBranchDeleteAndPrune

Force-deletes a local branch and prunes stale remote-tracking refs for origin. Without `-BranchName` it offers the local branches in a menu that takes one or more; Enter deletes nothing. Alias: `gbd`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
GitBranchDeleteAndPrune feature/done
GitBranchDeleteAndPrune -BranchName "feature/done"
gbd    # pick one or more branches from a menu
```

## Related

- [`GitBranchDeleteAndPrune` in the Git module reference](../../../modules/git.md#gitbranchdeleteandprune) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

# GitBranchDeleteAndPrune

Force-deletes a local branch and prunes stale remote-tracking refs for origin. Alias: `gbd`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
GitBranchDeleteAndPrune feature/done
GitBranchDeleteAndPrune -BranchName "feature/done"
```

## Related

- [`GitBranchDeleteAndPrune` in the Git module reference](../../../modules/git.md#gitbranchdeleteandprune) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

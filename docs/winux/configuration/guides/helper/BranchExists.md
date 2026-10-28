# BranchExists

Checks whether a Git branch exists in the local repository.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
BranchExists -Branch MyRepo
if (BranchExists -Branch "feature/my-feature") { ... }
```

## Related

- [`BranchExists` in the Helper module reference](../../../modules/helper.md#branchexists) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

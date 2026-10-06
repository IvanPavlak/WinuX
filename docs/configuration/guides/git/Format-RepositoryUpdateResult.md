# Format-RepositoryUpdateResult

Turns one repository update result into the one-line summary `Update-Repositories -Quiet` prints, with the level to print it at and the totals bucket it counts towards.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It formats what [`Update-Repository`](Update-Repository.md) returns; the compact form is chosen by `Update-Repositories -Quiet`, which the startup update uses.

## Usage

```powershell
Format-RepositoryUpdateResult -Result (Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -Quiet)
```

## Related

- [`Format-RepositoryUpdateResult` in the Git module reference](../../../modules/git.md#format-repositoryupdateresult) - parameters, usage and behaviour
- [`Update-Repositories`](Update-Repositories.md) - the caller
- [Git configuration guides](README.md) - every guide for this module

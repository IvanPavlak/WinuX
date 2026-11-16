# Sync-RepositoryHooks

Turns one clone's tracked git hooks on or off, by writing or taking back `core.hooksPath` in the clone's local git configuration.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The hooks folder is handed to it by its callers, which read the `Hooks` key of a `RepositoryGroups` entry: [`Update-Repositories`](Update-Repositories.md) and [`Initialize-Repository`](Initialize-Repository.md).

## Usage

```powershell
Sync-RepositoryHooks -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -HooksPath ".githooks"
Sync-RepositoryHooks -Name MyRepo -LocalPath "<DevRoot>\MyRepo"
```

## Related

- [`Sync-RepositoryHooks` in the Git module reference](../../../modules/git.md#sync-repositoryhooks) - parameters, usage and behaviour
- [`Update-Repositories`](Update-Repositories.md) - where the `Hooks` key is configured
- [`Get-RepositoryHooks`](Get-RepositoryHooks.md) - lists every marked repository with the value found in its clone
- [Git configuration guides](README.md) - every guide for this module

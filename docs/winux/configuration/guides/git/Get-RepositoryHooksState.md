# Get-RepositoryHooksState

Reads the record of every `core.hooksPath` the repository update wrote on this machine (`%LOCALAPPDATA%\WinuX\repository-hooks.state`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It is the record [`Sync-RepositoryHooks`](Sync-RepositoryHooks.md) keeps so that a removed `Hooks` mark takes back only the value the mechanism wrote.

## Usage

```powershell
Get-RepositoryHooksState
(Get-RepositoryHooksState).Entries
```

## Related

- [`Get-RepositoryHooksState` in the Git module reference](../../../modules/git.md#get-repositoryhooksstate) - parameters, usage and behaviour
- [`Sync-RepositoryHooks`](Sync-RepositoryHooks.md) - the writer of the record
- [`Get-RepositoryHooks`](Get-RepositoryHooks.md) - lists what is recorded but no longer marked
- [Git configuration guides](README.md) - every guide for this module

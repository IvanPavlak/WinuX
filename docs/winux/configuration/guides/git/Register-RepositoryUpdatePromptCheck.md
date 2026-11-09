# Register-RepositoryUpdatePromptCheck

Deprecated: makes a shell that stays open into the next day run the daily repository update at its first prompt after the day starts.

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0.** The automatic repository update is a startup task now, and [`Register-StartupTaskPromptCheck`](../workflow/Register-StartupTaskPromptCheck.md) does this for every startup task that runs once per day in a newly opened terminal. The profile calls that one and no longer calls this function, which still works on its own until 3.0.0 and warns once per session. It reads only the deprecated `RepositoryUpdate.Startup` keys, so it does nothing for a `RepositoryUpdate` task written under `Startup.Tasks`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It acts on the deprecated [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) keys through [`Get-RepositoryUpdateStartupSettings`](Get-RepositoryUpdateStartupSettings.md); their replacement, one `Startup.Tasks` entry, is on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
# Deprecated
Register-RepositoryUpdatePromptCheck

# The replacement
Register-StartupTaskPromptCheck
```

## Related

- [`Register-RepositoryUpdatePromptCheck` in the Git module reference](../../../modules/git.md#register-repositoryupdatepromptcheck) - parameters, usage and behaviour
- [`Register-StartupTaskPromptCheck`](../workflow/Register-StartupTaskPromptCheck.md) - the replacement
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the migration to a startup task
- [Git configuration guides](README.md) - every guide for this module

# Invoke-RepositoryUpdatePromptCheck

Deprecated: the prompt function the daily repository update installed - the original prompt, plus the update at the first prompt after the day starts.

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0.** The automatic repository update is a startup task now, and [`Invoke-StartupTaskPromptCheck`](../workflow/Invoke-StartupTaskPromptCheck.md) replaces this function: it is the prompt the profile's startup tasks install. This function keeps working until 3.0.0, through the deprecated `Invoke-StartupRepositoryUpdate`, which runs the startup task `RepositoryUpdate` and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. When it runs at all follows the deprecated [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) keys; their replacement, one `Startup.Tasks` entry, is on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
# Deprecated, and not called by hand: Register-RepositoryUpdatePromptCheck makes it the body of the prompt function
Invoke-RepositoryUpdatePromptCheck

# The replacement, installed by Register-StartupTaskPromptCheck
Invoke-StartupTaskPromptCheck
```

## Related

- [`Invoke-RepositoryUpdatePromptCheck` in the Git module reference](../../../modules/git.md#invoke-repositoryupdatepromptcheck) - parameters, usage and behaviour
- [`Invoke-StartupTaskPromptCheck`](../workflow/Invoke-StartupTaskPromptCheck.md) - the replacement
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the migration to a startup task
- [Git configuration guides](README.md) - every guide for this module

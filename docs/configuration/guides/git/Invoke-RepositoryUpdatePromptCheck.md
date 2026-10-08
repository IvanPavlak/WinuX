# Invoke-RepositoryUpdatePromptCheck

The prompt function the daily repository update installs: the original prompt, plus the update at the first prompt after the day starts.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. When it runs at all is set on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
# Not called by hand: Register-RepositoryUpdatePromptCheck makes it the body of the prompt function
Invoke-RepositoryUpdatePromptCheck
```

## Related

- [`Invoke-RepositoryUpdatePromptCheck` in the Git module reference](../../../modules/git.md#invoke-repositoryupdatepromptcheck) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

# Register-RepositoryUpdatePromptCheck

Makes a shell that stays open into the next day run the daily repository update at its first prompt after the day starts.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It acts on [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) through [`Get-RepositoryUpdateStartupSettings`](Get-RepositoryUpdateStartupSettings.md), configured on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
Register-RepositoryUpdatePromptCheck
```

## Related

- [`Register-RepositoryUpdatePromptCheck` in the Git module reference](../../../modules/git.md#register-repositoryupdatepromptcheck) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module

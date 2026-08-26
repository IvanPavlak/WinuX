# Configure-NuGetConfig

Configures NuGet package source settings for the GitHub Package Registry by copying a NuGet.config template from the WinuX repository to the user's AppData NuGet folder.

> [!NOTE]
> An existing real `NuGet.Config` at the destination (which may carry credentials for feeds the template knows nothing about) is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/NuGetConfig/<timestamp>/`, gitignored) before it is overwritten; if the backup cannot be taken the write is aborted.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Configure-NuGetConfig
Configure-NuGetConfig -Override
```

## Related

- [`Configure-NuGetConfig` in the System module reference](../../../modules/system.md#configure-nugetconfig) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

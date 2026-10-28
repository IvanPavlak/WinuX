# Show-PinnedAppsWarning

Prints a yellow warning listing apps that are pinned (version-locked) to a specific version and will be skipped by the upgrade functions.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Show-PinnedAppsWarning -PinnedApps @("git", "nodejs")
Show-PinnedAppsWarning -PinnedApps @("git") -Message "Version-locked packages"
```

## Related

- [`Show-PinnedAppsWarning` in the System module reference](../../../modules/system.md#show-pinnedappswarning) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

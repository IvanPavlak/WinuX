# Resolve-PackageManagers

The single gate deciding which of WinGet, Scoop and Chocolatey WinuX installs and upgrades.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PackageManagers`](../../configuration-reference.md#packagemanagers) | array of manager names | `@("WinGet")` | Which package managers Bootstrap provisions and installs from. `Resolve-PackageManagers` filters the list by machine type. |

## Decisions

1. Which package managers do you want on this machine?
    - Options: Any of `WinGet`, `Scoop`, `Chocolatey`. The array replaces wholesale, so list all of them you want.
    - Default: `@("WinGet")`.
    - More detail: [`PackageManagers`](../../configuration-reference.md#packagemanagers)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `PackageManagers` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `PackageManagers`
2. Reload and confirm the merge landed

## Step 1: Set `PackageManagers`

Which package managers Bootstrap provisions and installs from. `Resolve-PackageManagers` filters the list by machine type.

```powershell
PackageManagers = @("WinGet", "Scoop")
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PackageManagers
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PackageManagers
Resolve-PackageManagers
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PackageManagers = @("WinGet", "Scoop")
}
```

## Related

- [`Resolve-PackageManagers` in the Bootstrap module reference](../../../modules/bootstrap.md#resolve-packagemanagers) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Install-ChocolateyApps`](../application/Install-ChocolateyApps.md) - reads the same configuration
- [`Install-ScoopApps`](../application/Install-ScoopApps.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

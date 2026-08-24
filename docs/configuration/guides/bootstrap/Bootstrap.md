# Bootstrap

The main orchestration function and heart of WinuX.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig) | hashtable, 9 keys | hashtable, 9 keys | Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands. |
| [`DefaultDisplayLanguage`](../../configuration-reference.md#locale--language) | string | empty string | The Windows display language `Set-DisplayLanguage` applies when called with no argument. Ships empty, so the function no-ops until you set it. |
| [`DefaultKeyboardLayoutSet`](../../configuration-reference.md#keyboard-layouts) | string | empty string | Which named set from `KeyboardLayoutSets` `Set-KeyboardLayouts` applies by default. Ships empty, so the function no-ops. |
| [`DefaultLocale`](../../configuration-reference.md#locale--language) | string | empty string | The locale `Set-Locale` applies by default. Ships empty, so the function no-ops. |
| [`DefaultMachineType`](../../configuration-reference.md#default-machine-type) | string | `"Test"` | The machine type used when the hostname is not in `HostnameToMachineType`. This is the safety net behind machine detection. |
| [`DefaultNerdFont`](../../configuration-reference.md#more-sections-quick-reference) | string | empty string | Which entry from `NerdFonts` Bootstrap installs and `Configure-NerdFont` applies. Ships empty, so the function no-ops. |
| [`GitConfig`](../../configuration-reference.md#git-configuration) | hashtable, 3 keys | `@{ UserName = ""; UserEmail = ""; WingetPackageId = "Git.Git" }` | The Git identity `Install-Git` writes into the global Git config, and the WinGet package it installs Git from. Ships with an empty identity on purpose - it is personal data. |

This is the widest configuration surface in WinuX - `Bootstrap` reads the step toggles plus every default the first-run sequence needs. Work through it after `Load-PathConfiguration` and `Expand-ConfigPaths`: machine type and base paths gate everything else, and a wrong `BasePaths` entry makes every step downstream do the right thing in the wrong place.

## Decisions

1. Which bootstrap steps should run on this machine?
    - Options: Each entry under `BootstrapConfig.Steps` is either a boolean or a per-machine-type hashtable with a `Default` fallback. Steps that act the moment they run (`CoreAiRules`, taskbar, wallpaper) ship off.
    - Default: The shipped `Steps` map. Change only the steps you actually want to flip.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
2. Do you need to change where the app-list CSVs live?
    - Options: Repository-relative paths under `BootstrapConfig.DataFiles`, keyed `WinGetApps`, `ScoopApps`, `ChocolateyApps`.
    - Default: The shipped paths. Almost nobody changes these.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
3. Where should the bootstrap log be written?
    - Options: `LogFileLocation` (for example `Desktop`) plus `LogFilePrefix`.
    - Default: `Desktop` with prefix `BootstrapLog`.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
4. Which Windows display language should be the default?
    - Options: A key from your `DisplayLanguages` map.
    - Default: Empty - `Set-DisplayLanguage` reports that nothing is configured and returns.
    - More detail: [`DefaultDisplayLanguage`](../../configuration-reference.md#locale--language)
5. Which keyboard layout set should be the default?
    - Options: A key from your `KeyboardLayoutSets` map.
    - Default: Empty - `Set-KeyboardLayouts` no-ops.
    - More detail: [`DefaultKeyboardLayoutSet`](../../configuration-reference.md#keyboard-layouts)
6. Which locale should be the default?
    - Options: A key from your `Locales` map.
    - Default: Empty - `Set-Locale` no-ops.
    - More detail: [`DefaultLocale`](../../configuration-reference.md#locale--language)
7. Which machine type should an unrecognised hostname fall back to?
    - Options: A member of `ValidMachineTypes`. Pick the most conservative type you have.
    - Default: `Test`.
    - More detail: [`DefaultMachineType`](../../configuration-reference.md#default-machine-type)
8. Which Nerd Font should be installed and used?
    - Options: A key from your `NerdFonts` map, e.g. `JetBrainsMono`.
    - Default: Empty - `Configure-NerdFont` no-ops.
    - More detail: [`DefaultNerdFont`](../../configuration-reference.md#more-sections-quick-reference)
9. What Git user name should be configured?
    - Options: Your display name as you want it on commits.
    - Default: Empty - `Install-Git` installs Git but configures no identity.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)
10. What Git email should be configured?
    - Options: The address you want on commits, e.g. `you@example.com`.
    - Default: Empty.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)
11. Do you need a different Git package?
    - Options: A WinGet package id.
    - Default: `Git.Git`.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BootstrapConfig`
2. Set `DefaultDisplayLanguage`
3. Set `DefaultKeyboardLayoutSet`
4. Set `DefaultLocale`
5. Set `DefaultMachineType`
6. Set `DefaultNerdFont`
7. Set `GitConfig`
8. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig`

Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands.

```powershell
BootstrapConfig = @{
    Steps = @{
        CoreAiRules = $true
    }
}
```

## Step 2: Set `DefaultDisplayLanguage`

The Windows display language `Set-DisplayLanguage` applies when called with no argument. Ships empty, so the function no-ops until you set it.

```powershell
DefaultDisplayLanguage = "English"
```

## Step 3: Set `DefaultKeyboardLayoutSet`

Which named set from `KeyboardLayoutSets` `Set-KeyboardLayouts` applies by default. Ships empty, so the function no-ops.

```powershell
DefaultKeyboardLayoutSet = "Standard"
```

## Step 4: Set `DefaultLocale`

The locale `Set-Locale` applies by default. Ships empty, so the function no-ops.

```powershell
DefaultLocale = "English"
```

## Step 5: Set `DefaultMachineType`

The machine type used when the hostname is not in `HostnameToMachineType`. This is the safety net behind machine detection.

```powershell
DefaultMachineType = "Test"
```

## Step 6: Set `DefaultNerdFont`

Which entry from `NerdFonts` Bootstrap installs and `Configure-NerdFont` applies. Ships empty, so the function no-ops.

```powershell
DefaultNerdFont = "JetBrainsMono"
```

## Step 7: Set `GitConfig`

The Git identity `Install-Git` writes into the global Git config, and the WinGet package it installs Git from. Ships with an empty identity on purpose - it is personal data.

```powershell
GitConfig = @{
    UserName = "Your Name"
    UserEmail = "you@example.com"
}
```

## Step 8: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig
$global:Configuration.DefaultDisplayLanguage
$global:Configuration.DefaultKeyboardLayoutSet
$global:Configuration.DefaultLocale
$global:Configuration.DefaultMachineType
$global:Configuration.DefaultNerdFont
$global:Configuration.GitConfig
Resolve-BootstrapSteps | Format-Table
Resolve-PackageManagers
DetermineMachineType
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        Steps = @{
            CoreAiRules = $true
        }
    }
    DefaultDisplayLanguage = "English"
    DefaultKeyboardLayoutSet = "Standard"
    DefaultLocale = "English"
    DefaultMachineType = "Test"
    DefaultNerdFont = "JetBrainsMono"
    GitConfig = @{
        UserName = "Your Name"
        UserEmail = "you@example.com"
    }
}
```

## Related

- [`Bootstrap` in the Bootstrap module reference](../../../modules/bootstrap.md#bootstrap) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Create-CondaEnvironments`](../application/Create-CondaEnvironments.md) - reads the same configuration
- [`Start-Win11Debloat`](../application/Start-Win11Debloat.md) - reads the same configuration
- [`Update-Win11DebloatVendor`](../application/Update-Win11DebloatVendor.md) - reads the same configuration
- [`Invoke-PersonalSteps`](Invoke-PersonalSteps.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

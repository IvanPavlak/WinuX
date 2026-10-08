# Resolve-VSCodeProfilesConfig

Resolves the `VSCodeProfiles` section into expanded paths, the catalogue and this machine type's selection, shared by `Deploy-VSCodeProfiles` and `Export-VSCodeProfile`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`VSCodeProfiles.Root`](../../configuration-reference.md#vs-code-profiles) | string | `{RepoRoot}\VSCode\Profiles` | `Root`, and each entry's `Source` beneath it. |
| [`VSCodeProfiles.UserData`](../../configuration-reference.md#vs-code-profiles) | string | `{AppData}\Code\User` | `UserData`. |
| [`VSCodeProfiles.SettingsSync`](../../configuration-reference.md#vs-code-profiles) | boolean | `$false` | `SettingsSync`. |
| [`VSCodeProfiles.Prune`](../../configuration-reference.md#vs-code-profiles) | boolean | `$false` | `Prune`. |
| [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles) | ordered array | `@()` (empty) | `Entries`, in catalogue order. |
| [`VSCodeProfiles.Deploy`](../../configuration-reference.md#vs-code-profiles) | hashtable | `@{ Default = @() }` | `Selected` and `Unknown` for the machine type. |

## Decisions

1. Which entries should this machine type select?
    - Options: Its own key in `Deploy`; without one, the `Default` list; without that, none.
    - Default: `Default = @()` - none.
    - More detail: [`VSCodeProfiles.Deploy`](../../configuration-reference.md#vs-code-profiles)

The other keys are decided on the [Deploy-VSCodeProfiles](Deploy-VSCodeProfiles.md) guide.

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `VSCodeProfiles`
2. Reload and read the resolution back

## Step 1: Set `VSCodeProfiles`

```powershell
VSCodeProfiles = @{
    Catalogue = @(@{ MyProfile = @{ Target = "Default" } })
    Deploy    = @{ Default = @("MyProfile") }
}
```

## Step 2: Reload and read the resolution back

```powershell
Reload-PowerShellProfile
Resolve-VSCodeProfilesConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-VSCodeProfilesConfig).Selected
(Resolve-VSCodeProfilesConfig -MachineType Work).Selected
(Resolve-VSCodeProfilesConfig).Unknown
```

## Complete Example

```powershell
# Configuration.local.psd1
@{
    VSCodeProfiles = @{
        Root         = "{RepoRoot}\VSCode\Profiles"
        UserData     = "{AppData}\Code\User"
        SettingsSync = $false
        Prune        = $false
        Catalogue    = @(@{ MyProfile = @{ Target = "Default" } })
        Deploy       = @{ Default = @("MyProfile") }
    }
}
```

## Related

- [`Resolve-VSCodeProfilesConfig` in the Application module reference](../../../modules/application.md#resolve-vscodeprofilesconfig)
- [`Deploy-VSCodeProfiles`](Deploy-VSCodeProfiles.md) - the walkthrough of every key
- [Application configuration guides](README.md)
- [WinuXConfigurator](../../winux-configurator.md)

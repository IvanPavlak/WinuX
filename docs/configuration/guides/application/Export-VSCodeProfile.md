# Export-VSCodeProfile

Captures the live VS Code profile a catalogue entry deploys onto into the entry's folder in the repository: its real files and a merged `extensions.txt`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles) | ordered array | `@()` (empty) | The entry `-Name` captures and the VS Code profile it reads (`Target`). |
| [`VSCodeProfiles.Root`](../../configuration-reference.md#vs-code-profiles) | string | `{RepoRoot}\VSCode\Profiles` | Where the entry's folder is written. |
| [`VSCodeProfiles.UserData`](../../configuration-reference.md#vs-code-profiles) | string | `{AppData}\Code\User` | VS Code's user data folder the profile is read from. |

## Decisions

1. Which profile should be captured, and onto which catalogue entry?
    - Options: Add the entry to the catalogue first, with `Target` naming the VS Code profile to read (`"Default"` for VS Code's built-in profile).
    - Default: None - a name the catalogue does not carry is refused.
    - More detail: [`VSCodeProfiles.Catalogue`](../../configuration-reference.md#vs-code-profiles)
2. Where should the captured folder go?
    - Options: Any folder; `{RepoRoot}`, `{User}` and `{AppData}` expand. Each entry gets `<Root>\<entry>\`.
    - Default: `{RepoRoot}\VSCode\Profiles`.
    - More detail: [`VSCodeProfiles.Root`](../../configuration-reference.md#vs-code-profiles)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Add the catalogue entry
2. Capture and review

## Step 1: Add the catalogue entry

```powershell
VSCodeProfiles = @{
    Catalogue = @(
        @{ MyProfile = @{ Target = "Default" } }
    )
}
```

## Step 2: Capture and review

```powershell
Reload-PowerShellProfile
Export-VSCodeProfile -Name MyProfile
git diff -- VSCode/Profiles/MyProfile
```

Files already linked into the repository are left alone. `extensions.txt` keeps its comments and pins; delete the lines of extensions you do not want deployed, disabled ones included.

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-VSCodeProfilesConfig).Entries["MyProfile"]
Get-VSCodeProfileLocation -Name ((Resolve-VSCodeProfilesConfig).Entries["MyProfile"].Target)
Get-ChildItem ((Resolve-VSCodeProfilesConfig).Entries["MyProfile"].Source)
```

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    VSCodeProfiles = @{
        Root      = "{RepoRoot}\VSCode\Profiles"
        UserData  = "{AppData}\Code\User"
        Catalogue = @(
            @{ MyProfile = @{ Target = "Default" } }
        )
    }
}
```

## Related

- [`Export-VSCodeProfile` in the Application module reference](../../../modules/application.md#export-vscodeprofile)
- [`Deploy-VSCodeProfiles`](Deploy-VSCodeProfiles.md) - deploys what this function captures
- [Application configuration guides](README.md)
- [WinuXConfigurator](../../winux-configurator.md)

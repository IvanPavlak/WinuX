# Open-LeagueOfLegends

Opens the League of Legends client via `Start-Application`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.LeagueOfLegendsExe`](../../configuration-reference.md#application-executables) | string (path) | `""` (empty) | What `Open-LeagueOfLegends` starts (path validation skipped, so a Start-menu shortcut works too). Empty, the launch fails with an error. Placeholders such as `{User}` expand. |

## Decisions

1. Where is the League of Legends client on this machine?
    - Options: The client executable, or its Start-menu entry, e.g. `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Riot Games\League of Legends`.
    - Default: Empty - `Open-LeagueOfLegends` reports an error until it is set.
    - More detail: [`Universal`](../../configuration-reference.md#application-executables)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal`
2. Reload and confirm the merge landed

## Step 1: Set `Universal`

The client to start. `Universal` is a hashtable and deep-merges, so setting only this key keeps the rest of `Universal`.

```powershell
Universal = @{
    LeagueOfLegendsExe = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Riot Games\League of Legends"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.LeagueOfLegendsExe
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        LeagueOfLegendsExe = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Riot Games\League of Legends"
    }
}
```

## Related

- [`Open-LeagueOfLegends` in the Application module reference](../../../modules/application.md#open-leagueoflegends) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-NotepadPlusPlus`](Open-NotepadPlusPlus.md) - reads the same configuration
- [`Open-Steam`](Open-Steam.md) - reads the same configuration
- [`Open-VisualStudio`](Open-VisualStudio.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

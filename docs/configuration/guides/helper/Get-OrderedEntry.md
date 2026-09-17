# Get-OrderedEntry

Looks one entry up by name in an ordered configuration section - the lookup counterpart of [`Get-OrderedNames`](Get-OrderedNames.md), which returns the menu.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

`Get-OrderedEntry` takes the section it works on from its caller rather than reading a fixed key, so there is no key table for it.

Where `Get-OrderedNames` returns the menu, this returns what the selected name carries: the action list behind a workspace, the PDF paths behind a group, the MAC address behind a machine. It reads the same sections - `ProjectActions`, `WorkspaceActions`, `CampaignResources`, `AcrobatPdfGroups`, `WakeOnLanConfig`, `Locales`, `KeyboardLayoutSets`, `NerdFonts` - and the same two shapes, the ordered array and, for a fork that has not migrated, a plain hashtable. Name matching is case-insensitive and the first match wins, so a section that lists a name twice behaves like the file reads, top to bottom. An unconfigured name comes back as `$null` and the caller decides what that means.

## Decisions

1. Which ordered section holds the entry you are trying to change?
    - Options: any of the sections above. The guide for the function that consumes it is the one with the decisions in it - see the [Helper guides index](README.md) and the module guide indexes.
    - Default: nothing to set. `Get-OrderedEntry` returns `$null` against an empty base configuration.
    - More detail: [Ordered Sections](../../configuration-reference.md#ordered-sections)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

An ordered section is an array, so this warning applies to every one of them: your local file restates the whole list rather than adding one entry to the base's.

## Steps Overview

1. Find the entry you want to change
2. Reload and confirm the merge landed

## Step 1: Find the entry you want to change

`Get-OrderedEntry` has no configuration of its own. Open the section in the [configuration reference](../../configuration-reference.md) and edit the value beside the name - the key is the name the menu shows, the value is what that name does:

```powershell
WorkspaceActions = @(
    @{ WinuX = @(                    # <- the name
            @{ Action = "Open-VSCode"; Parameters = @{ Folder = "WinuX" } }
        )                            # <- what Get-OrderedEntry returns for it
    }
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Get-OrderedEntry $global:Configuration.WorkspaceActions "WinuX"
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Get-OrderedNames $global:Configuration.WorkspaceActions
Get-OrderedEntry $global:Configuration.WorkspaceActions "WinuX"
Get-OrderedEntry $global:Configuration.WakeOnLanConfig "Proxmox Backup Server"
```

A `$null` back means the name is not configured - check its spelling against `Get-OrderedNames`. If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

`Get-OrderedEntry` needs no configuration of its own; what it reads is the shape of the section you give it:

```powershell
# Configuration.local.psd1
@{
    WorkspaceActions = @(
        @{ WinuX = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "WinuX" } } ) }
    )
}
```

## Related

- [`Get-OrderedEntry` in the Helper module reference](../../../modules/helper.md#get-orderedentry) - parameters, usage and behaviour
- [`Get-OrderedNames`](Get-OrderedNames.md) - the menu counterpart, same sections
- [Helper configuration guides](README.md) - every guide for this module
- [Ordered Sections](../../configuration-reference.md#ordered-sections) - the rule and every section that follows it
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

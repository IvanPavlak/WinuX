# Get-OrderedNames

Returns the entry names of an ordered configuration section, in the order the file writes them - the menu, for every consumer that has one.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

`Get-OrderedNames` takes the section it works on from its caller rather than reading a fixed key, so there is no key table for it.

It is the read side of the repository's one ordering rule, [Ordered Sections](../../configuration-reference.md#ordered-sections): a menu-bearing section is an array of single-key hashtables, and this function returns those keys in file order. The sections it is called against are `ProjectActions`, `WorkspaceActions`, `CampaignResources`, `AcrobatPdfGroups`, `WakeOnLanConfig`, `Locales`, `KeyboardLayoutSets` and `NerdFonts` - each has its own guide, listed in the [Helper guides index](README.md) and the module indexes. A section still written as a plain hashtable is accepted and comes back sorted, because `Import-PowerShellDataFile` loses key order at load time; `Test-ConfigurationSchema` is what tells you to migrate it.

## Decisions

1. Which ordered section are you actually trying to reorder?
    - Options: any of the sections above. The guide for the function that consumes it is the one with the decisions in it - the order of a menu is decided by the order you write its entries, nowhere else.
    - Default: nothing to set. `Get-OrderedNames` returns an empty list against an empty base configuration.
    - More detail: [Ordered Sections](../../configuration-reference.md#ordered-sections)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

An ordered section is an array, so this warning applies to every one of them: your local file restates the whole list rather than adding one entry to the base's.

## Steps Overview

1. Find the ordered section whose menu you want to change
2. Reload and confirm the merge landed

## Step 1: Find the ordered section whose menu you want to change

`Get-OrderedNames` has no configuration of its own. Work out which menu you are trying to reorder, open that section in the [configuration reference](../../configuration-reference.md), and write its entries in the order you want them offered:

```powershell
WorkspaceActions = @(
    @{ Default = @( <actions> ) }   # offered first
    @{ WinuX   = @( <actions> ) }   # offered second
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Get-OrderedNames $global:Configuration.WorkspaceActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Get-OrderedNames $global:Configuration.WorkspaceActions
Get-OrderedNames $global:Configuration.ProjectActions
Test-ConfigurationSchema          # names any ordered section still written as a hashtable
```

If a section reads back alphabetical rather than in your order, it is still a hashtable - rewrite it as an array of single-key hashtables. If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

`Get-OrderedNames` needs no configuration of its own; what it reads is the shape of the section you give it:

```powershell
# Configuration.local.psd1
@{
    WorkspaceActions = @(
        @{ Default = @( @{ Action = "Open-Browser" } ) }
        @{ WinuX   = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "WinuX" } } ) }
    )
}
```

## Related

- [`Get-OrderedNames` in the Helper module reference](../../../modules/helper.md#get-orderednames) - parameters, usage and behaviour
- [`Get-OrderedEntry`](Get-OrderedEntry.md) - the lookup counterpart, same sections
- [Helper configuration guides](README.md) - every guide for this module
- [Ordered Sections](../../configuration-reference.md#ordered-sections) - the rule and every section that follows it
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

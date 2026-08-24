# Open-DnD

Opens the full D&D campaign workspace for a tabletop RPG session: the Obsidian vault with campaign notes, the rulebook PDF in Acrobat, and the spell/resource URLs in the browser.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`CampaignResources`](../../configuration-reference.md#more-sections-quick-reference) | hashtable of campaign name to resource map | hashtable, 1 key | What `Open-DnD` opens for each campaign: the per-campaign document, map and reference paths and URLs. |
| [`Campaigns`](../../configuration-reference.md#more-sections-quick-reference) | array of strings | array of 1 (`"ExampleCampaign"`) | The campaign names `Open-DnD` offers. Each needs a matching `CampaignResources` entry. |

## Decisions

1. Which resources belong to each campaign?
    - Options: Paths and URLs per campaign name. Placeholders allowed.
    - Default: Skip unless you use `Open-DnD`.
    - More detail: [`CampaignResources`](../../configuration-reference.md#more-sections-quick-reference)
2. Which campaigns should `Open-DnD` offer?
    - Options: One name per campaign.
    - Default: Skip unless you use `Open-DnD`.
    - More detail: [`Campaigns`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `Campaigns` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `CampaignResources`
2. Set `Campaigns`
3. Reload and confirm the merge landed

## Step 1: Set `CampaignResources`

What `Open-DnD` opens for each campaign: the per-campaign document, map and reference paths and URLs.

```powershell
CampaignResources = @{
    MyCampaign = @{
        Notes = "{User}\Documents\MyCampaign\Notes.md"
        Map   = "https://example.com/map"
    }
}
```

## Step 2: Set `Campaigns`

The campaign names `Open-DnD` offers. Each needs a matching `CampaignResources` entry.

```powershell
Campaigns = @("MyCampaign")
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.CampaignResources
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.CampaignResources
$global:Configuration.Campaigns
$global:Configuration.Campaigns
$global:Configuration.CampaignResources.Keys
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    CampaignResources = @{
        MyCampaign = @{
            Notes = "{User}\Documents\MyCampaign\Notes.md"
            Map   = "https://example.com/map"
        }
    }
    Campaigns = @("MyCampaign")
}
```

## Related

- [`Open-DnD` in the Workflow module reference](../../../modules/workflow.md#open-dnd) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

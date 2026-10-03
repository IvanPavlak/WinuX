# Get-AiModRoster

Walks the mods root and returns the flattened roster - mod name to path and source - that `Deploy-AiMods` links from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMods.Root`](../../configuration-reference.md#ai-mods) | string | `{RepoRoot}\AI\Mods` | The folder walked when `-Root` is not supplied. Read through [`Resolve-AiModsConfig`](Resolve-AiModsConfig.md), so `{RepoRoot}`, `{User}` and `{AppData}` are expanded. |

Nothing else. The roster is a reading of the disk, not of the configuration: what counts as a mod (`<source>\<mod>\.claude-plugin\plugin.json`) and how a name collision is resolved (first source alphabetically) are fixed rules, not settings.

## Decisions

1. Where do the mods live?
    - Options: Leave `AiMods.Root` at the default so the roster comes from the repository, or point it elsewhere if your mods are not kept in the repo.
    - Default: `{RepoRoot}\AI\Mods`, one subfolder per source.
    - More detail: [`AiMods`](../../configuration-reference.md#ai-mods)
2. Do you need to configure this function at all?
    - Options: In practice no - configure `AiMods` once on the [`Resolve-AiModsConfig`](Resolve-AiModsConfig.md) or [`Deploy-AiMods`](Deploy-AiMods.md) page and every reader of the section follows, this one included. Pass `-Root` for a one-off walk of a different tree.
    - Default: The resolved `AiMods.Root`.
    - More detail: [`AiMods`](../../configuration-reference.md#ai-mods)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiMods.Root` (only when the mods do not live in the repository)
2. Reload and confirm the roster reads back

## Step 1: Set `AiMods.Root`

Only when the default does not fit. `Root` is a scalar and replaces wholesale.

```powershell
AiMods = @{
    Root = "{RepoRoot}\AI\Mods"
}
```

## Step 2: Reload and confirm the roster reads back

```powershell
Reload-PowerShellProfile
(Get-AiModRoster).Root
(Get-AiModRoster).Mods.Count
```

An empty roster on a repository that does carry mods nearly always means `Root` points at the wrong folder, or that the folders under it hold no `.claude-plugin\plugin.json`.

## Verification

Read-only checks. None of these change anything.

```powershell
(Get-AiModRoster).Mods.Keys
(Get-AiModRoster).Duplicates
Get-AiModRoster -Root "C:\Repo\AI\Mods"
```

A non-empty `Duplicates` list means two sources carry the same mod name; the entry names which source won.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiMods = @{
        Root = "{RepoRoot}\AI\Mods"
    }
}
```

## Related

- [`Get-AiModRoster` in the AI module reference](../../../modules/ai.md#get-aimodroster) - parameters, usage and behaviour
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiMods`](Deploy-AiMods.md) - links the mods this roster lists
- [`Resolve-AiModsConfig`](Resolve-AiModsConfig.md) - where `AiMods.Root` is actually configured
- [Configuration reference](../../configuration-reference.md) - every key, section by section

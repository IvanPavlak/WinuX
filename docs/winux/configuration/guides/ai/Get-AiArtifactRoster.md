# Get-AiArtifactRoster

Walks one kind of the artifacts root and returns the flattened roster - item name to path and source - that `Deploy-AiArtifacts` and `List-AiArtifacts` both work from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts.Root`](../../configuration-reference.md#ai-artifacts) | string | `{RepoRoot}\AI` | The folder walked: `<Root>\<Kind>\<source>\<item>`. |
| [`AiArtifacts.Sources`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{}` (empty) | Which source folders besides `own`, `winux` and `example` are read. |
| [`AiArtifacts.Exclude`](../../configuration-reference.md#ai-artifacts) | array | `@()` | Items left out of the roster. |
| [`AiArtifacts.Checkouts`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{}` | Local repositories read right after `own`, items linked from their working tree. |
| [`AiArtifacts.Manifests`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{}` | Manifest files read last; their rows come from the manifest cache. |
| [`AiProfiles`](../../configuration-reference.md#ai-profiles) | hashtable | no profile | The active profile's `Exclude` and `Include` entries, and the profile name manifest rows are scoped to. |

All of them are read through [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md). What counts as an item and how a name collision is resolved (`own`, checkouts, `winux`, `example`, vendored, manifests; the first wins) are fixed rules, not settings, because the listing and the deployment must agree.

## Decisions

1. Do you need to configure this function at all?
    - Options: No - configure `AiArtifacts` once on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page and every reader follows, this one included. Pass `-Config` to walk with a resolved configuration of your own.
    - Default: The resolved `AiArtifacts`.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiArtifacts` on the `Deploy-AiArtifacts` page
2. Reload and confirm the merge landed

## Step 1: Set `AiArtifacts` on the `Deploy-AiArtifacts` page

```powershell
AiArtifacts = @{
    Exclude = @("skills/tdd")
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
(Get-AiArtifactRoster -Kind Skills).Items.Keys
```

## Verification

Read-only checks. None of these change anything.

```powershell
(Get-AiArtifactRoster -Kind Skills).Items.Count
(Get-AiArtifactRoster -Kind Rules).Items['CoreAiRules'].Source
(Get-AiArtifactRoster -Kind Skills).Duplicates
```

A non-empty `Duplicates` list means two sources carry the same item name; the entry names which source won.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiArtifacts = @{
        Root    = "{RepoRoot}\AI"
        Sources = @{ mattpocock = @{ Repository = "OWNER/skills"; Skills = @("skills/engineering") } }
        Exclude = @("skills/tdd", "rules/example/CoreAiRules")
    }
}
```

## Related

- [`Get-AiArtifactRoster` in the AI module reference](../../../modules/ai.md#get-aiartifactroster) - the returned roster
- [AI Artifacts](../../../ai/artifacts.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Get-AiArtifactPlan`](Get-AiArtifactPlan.md) - joins this roster with the harnesses
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

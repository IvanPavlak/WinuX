# Get-AiArtifactPlan

Builds the deployment plan of the AI artifacts - every destination of the harnesses this machine deploys into, with the items that go there - which `Deploy-AiArtifacts` carries out and `List-AiArtifacts -ListDiscrepancies` checks.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts.Deploy`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{ Default = @() }` | Which harnesses are planned for this machine type. |
| [`AiArtifacts.Use`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{ Rules = "CoreAiRules" }` | The item each `File` destination takes. |
| [`AiHarnesses`](../../configuration-reference.md#ai-harnesses) | hashtable | the shipped catalogue | The destinations of each harness. |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array | the repository itself | Where a `repo:<name>` manifest row's repository is, by name; its skills are planned into `<repository>\.claude\skills`. |

All of them are read through [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md); the items come from [`Get-AiArtifactRoster`](Get-AiArtifactRoster.md).

## Decisions

1. Do you need to configure this function at all?
    - Options: No - configure `AiArtifacts` and `AiHarnesses` on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page. Pass `-Kind` to plan some kinds only, `-Config` to plan another resolved configuration.
    - Default: Every kind, the resolved configuration.
    - More detail: [`AiHarnesses`](../../configuration-reference.md#ai-harnesses)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiArtifacts.Deploy` on the `Deploy-AiArtifacts` page
2. Reload and confirm the merge landed

## Step 1: Set `AiArtifacts.Deploy` on the `Deploy-AiArtifacts` page

```powershell
AiArtifacts = @{
    Deploy = @{ Default = @("claude-code", "codex") }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
(Get-AiArtifactPlan).Destinations | ForEach-Object { "$($_.Harness) $($_.Kind) $($_.Path): $($_.Items.Count)" }
```

## Verification

Read-only checks. None of these change anything.

```powershell
$plan = Get-AiArtifactPlan
$plan.Warnings
$plan.Notes
(Get-AiArtifactPlan -Kind Rules).Destinations.Items | Select-Object Name, Source, Target, WSLTarget
```

An empty `Warnings` list means every harness, destination and `Use` entry resolved.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiArtifacts = @{
        Use    = @{ Rules = "CoreAiRules" }
        Deploy = @{ Default = @("claude-code", "codex"); Work = @("claude-code") }
    }
}
```

## Related

- [`Get-AiArtifactPlan` in the AI module reference](../../../modules/ai.md#get-aiartifactplan) - the returned plan
- [AI Artifacts](../../../ai/artifacts.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) - carries the plan out
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

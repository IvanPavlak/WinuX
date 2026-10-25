# List-AiArtifacts

Lists the AI skills, mods, rules, prompts and agents the repository carries, grouped by kind and source, and with `-ListDiscrepancies` checks that each one is deployed into the apps this machine uses.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts`](../../configuration-reference.md#ai-artifacts) | hashtable | see the reference | `Root`, `Sources` and `Exclude` decide the roster; `Deploy`, `Use` and `AiHarnesses` decide what `-ListDiscrepancies` expects. Read through [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md). |
| [`ShowFunctionDetailsColors`](../../configuration-reference.md#console-colors) | hashtable | the shipped palette | The colours of each entry, shared with `List-Functions`. |

## Decisions

1. Do you need to configure this function at all?
    - Options: No - it lists what [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) deploys, so configure `AiArtifacts` there and this listing follows.
    - Default: The resolved `AiArtifacts`.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)
2. Should the catalog use different colours?
    - Options: Change `ShowFunctionDetailsColors`; `List-Functions` changes with it.
    - Default: The shipped palette.
    - More detail: [`ShowFunctionDetailsColors`](../../configuration-reference.md#console-colors)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Configure `AiArtifacts` on the `Deploy-AiArtifacts` page
2. Reload and confirm the merge landed

## Step 1: Configure `AiArtifacts` on the `Deploy-AiArtifacts` page

Everything this listing reads is decided there; see [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md).

```powershell
AiArtifacts = @{
    Exclude = @("rules/example/CoreAiRules")
    Deploy  = @{ Default = @("claude-code") }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
List-AiArtifacts -Kind Skills
```

## Verification

Read-only checks. None of these change anything.

```powershell
List-AiArtifacts
List-AiArtifacts -Kind Rules
List-AiArtifacts -ListDiscrepancies
```

`-ListDiscrepancies` reads the Windows destinations only; `Deploy-AiArtifacts -WhatIf` covers the rest, and `Deploy-AiArtifacts` reconciles the WSL twins.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiArtifacts = @{
        Exclude = @("rules/example/CoreAiRules")
        Deploy  = @{ Default = @("claude-code", "codex") }
    }
}
```

## Related

- [`List-AiArtifacts` in the AI module reference](../../../modules/ai.md#list-aiartifacts) - parameters, usage and behaviour
- [AI Artifacts](../../../ai/artifacts.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) - deploys what this function lists
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

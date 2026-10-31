# Resolve-AiArtifactsConfig

Resolves the `AiArtifacts` and `AiHarnesses` sections into the expanded values every AI artifact function shares, for one machine type.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts`](../../configuration-reference.md#ai-artifacts) | hashtable | `Root = "{RepoRoot}\AI"`, empty `Sources`, `Exclude` and `Deploy`, `Use = @{ Rules = "CoreAiRules" }` | The artifacts root, the vendored sources, the exclusions, the item each `File` destination takes and the harnesses per machine type. |
| [`AiHarnesses`](../../configuration-reference.md#ai-harnesses) | hashtable | `claude-code`, `codex`, `gemini-cli`, `copilot` | The apps and their destinations, expanded for the harnesses `Deploy` names. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | Maps each `{User}` destination onto `/home/<user>/` for its WSL twin. Empty means no WSL twins. |
| [`AiProfiles`](../../configuration-reference.md#ai-profiles) | hashtable | no profile | The active profile's `Rules`, `Deploy`, `Include` and `Exclude`, resolved through [`Resolve-AiProfile`](Resolve-AiProfile.md). |
| [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type) | hashtable | per machine type | `{Dev}` in `Checkouts` and `Manifests` paths is `BasePaths.<MachineType>.Dev`, else the folder holding the repository. |

## Decisions

1. Do you need to configure this function at all?
    - Options: No - configure `AiArtifacts` and `AiHarnesses` once on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page and every reader follows. Pass `-MachineType` to see another machine type's result.
    - Default: The merged configuration, for `$global:MachineType`.
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
    Deploy = @{ Default = @("claude-code") }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
$resolved = Resolve-AiArtifactsConfig
$resolved.Deploy
$resolved.Unknown
```

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-AiArtifactsConfig).Root
(Resolve-AiArtifactsConfig -MachineType Work).Deploy
(Resolve-AiArtifactsConfig).Harnesses['claude-code'].Destinations | Select-Object Kind, Placement, Path, WSLPath
```

An empty `Unknown` list means every `Deploy` name has an `AiHarnesses` entry.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLUsername = "you"
    AiArtifacts        = @{
        Sources = @{
            mattpocock = @{ Repository = "OWNER/skills"; Skills = @("skills/engineering") }
        }
        Exclude = @("rules/example/CoreAiRules")
        Use     = @{ Rules = @{ Default = "CoreAiRules"; Work = "WorkRules" } }
        Deploy  = @{ Default = @("claude-code", "codex"); Work = @("claude-code") }
    }
}
```

## Related

- [`Resolve-AiArtifactsConfig` in the AI module reference](../../../modules/ai.md#resolve-aiartifactsconfig) - the returned keys
- [AI Artifacts](../../../ai/artifacts.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

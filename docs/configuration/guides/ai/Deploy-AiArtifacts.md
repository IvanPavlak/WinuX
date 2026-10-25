# Deploy-AiArtifacts

Links the repository's AI skills, mods, rules, prompts and agents into the AI apps this machine deploys into (Claude Code, Codex, Gemini CLI, Copilot, or an app of your own), on Windows and inside WSL.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts.Deploy`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{ Default = @() }` | Per machine type, the `AiHarnesses` entries this machine deploys into. Empty means nothing is deployed. |
| [`AiArtifacts.Root`](../../configuration-reference.md#ai-artifacts) | string | `{RepoRoot}\AI` | The artifacts root: `<Root>\<Kind>\<source>\<item>`. |
| [`AiArtifacts.Exclude`](../../configuration-reference.md#ai-artifacts) | array | `@()` | Items not to deploy: `skills/tdd` (every source) or `rules/example/CoreAiRules` (one source); an entry may be `@{ Item = "..."; Machine = "Work" }`. |
| [`AiArtifacts.Use`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{ Rules = "CoreAiRules" }` | Per kind, the item a `File` destination takes (the rules linked as `CLAUDE.md`, `AGENTS.md`, ...); a value may be per machine type. |
| [`AiHarnesses`](../../configuration-reference.md#ai-harnesses) | hashtable | `claude-code`, `codex`, `gemini-cli`, `copilot` | The catalogue of apps and their destinations. Inactive until `Deploy` names an entry; add your own app with an entry of its own. |
| [`BootstrapConfig.Steps.AiArtifacts`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. The deprecated step names `CoreAiRules`, `AiSkills` and `AiMods` are its aliases until 2.0.0. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution the WSL twins are deployed in. Empty means Windows only. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL account whose home receives the WSL twins (`/home/<user>/...`). Empty means Windows only. |

## Decisions

1. Which AI apps should this machine deploy into?
    - Options: Any `AiHarnesses` entry names: `claude-code`, `codex`, `gemini-cli`, `copilot`, or one you define. One list per machine type under `Deploy`, `Default` for every type not listed.
    - Default: None - a vanilla machine deploys nothing.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)
2. Which rules should every app read as its global instructions?
    - Options: The name of a rules item under `AI\Rules\<source>\` in `Use.Rules`; write your own in `AI\Rules\own\<Name>\RULES.md` (plus `managed-settings.json` for Claude Code's managed settings).
    - Default: `CoreAiRules`, the example skeleton in `AI\Rules\example\CoreAiRules\`.
    - More detail: [CoreAiRules](../../../ai/coreairules.md)
3. Is there an artifact some or all machines should not get?
    - Options: `Exclude` entries `kind/name` or `kind/source/name`, optionally scoped with `Machine`. `rules/example/CoreAiRules` silences the name-clash warning once you have your own `CoreAiRules`.
    - Default: Nothing excluded.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)
4. Do you use an AI app the catalogue does not have?
    - Options: Add an `AiHarnesses` entry with its destinations (`Kind`, `Placement`, `Files`, `Path`, optional `Hooks`, `WSLPath`, `Machine`), then name it in `Deploy`.
    - Default: The four shipped entries.
    - More detail: [`AiHarnesses`](../../configuration-reference.md#ai-harnesses)
5. Should Bootstrap deploy the artifacts on every run?
    - Options: `$true` to deploy (and self-heal) on every Bootstrap; `$false` to run `Deploy-AiArtifacts` by hand.
    - Default: `$false`.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)
6. Should the artifacts also reach the apps running inside WSL?
    - Options: Set both `DefaultWSLDistribution` and `DefaultWSLUsername`; every harness with `WSL = $true` then gets its WSL twins.
    - Default: Empty - Windows only.
    - More detail: [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy. An `AiHarnesses` entry of the same name deep-merges, but its `Destinations` array replaces the base list wholesale.

## Steps Overview

1. Set `AiArtifacts.Deploy`
2. Name your rules with `AiArtifacts.Use` and leave items out with `AiArtifacts.Exclude`
3. Enable `BootstrapConfig.Steps.AiArtifacts`
4. Set `DefaultWSLDistribution` and `DefaultWSLUsername` for WSL
5. Reload and confirm the merge landed

## Step 1: Set `AiArtifacts.Deploy`

Turn harnesses on per machine type. `Default` covers every machine type without its own key.

```powershell
AiArtifacts = @{
    Deploy = @{
        Default = @("claude-code", "codex")
        Work    = @("claude-code")
    }
}
```

## Step 2: Name your rules and exclusions

Your own rules go in `AI\Rules\own\CoreAiRules\RULES.md`; `own` wins the name clash with the example, and the exclusion silences that warning.

```powershell
AiArtifacts = @{
    Use     = @{ Rules = "CoreAiRules" }
    Exclude = @("rules/example/CoreAiRules", @{ Item = "skills/tdd"; Machine = "Work" })
}
```

## Step 3: Enable `BootstrapConfig.Steps.AiArtifacts`

With the step on, Bootstrap runs `Deploy-AiArtifacts` after `SymbolicLinkMaker`, and every run self-heals the links.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiArtifacts = $true
    }
}
```

## Step 4: Set `DefaultWSLDistribution` and `DefaultWSLUsername`

The WSL twins are created as this user inside this distribution (Claude Code's `/etc/claude-code` link as root), pointing at the `/mnt/<drive>` mount of the repository.

```powershell
DefaultWSLDistribution = "Ubuntu"
DefaultWSLUsername     = "you"
```

## Step 5: Reload and confirm the merge landed

Reload the profile, then read the resolved values back. A deprecated key still in use is reported by `Test-ConfigurationSchema` at load.

```powershell
Reload-PowerShellProfile
(Resolve-AiArtifactsConfig).Deploy
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Deploy-AiArtifacts -WhatIf
List-AiArtifacts -ListDiscrepancies
(Get-Item "$env:USERPROFILE\.claude\CLAUDE.md").LinkTarget
Resolve-BootstrapSteps | Where-Object Name -eq "AiArtifacts"
```

`Deploy-AiArtifacts -WhatIf` ends with a success line or lists every `MISSING`, `WRONG`, `DIFFERS` and `STALE` entry. If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    DefaultWSLUsername     = "you"
    AiArtifacts            = @{
        Exclude = @("rules/example/CoreAiRules")
        Use     = @{ Rules = "CoreAiRules" }
        Deploy  = @{
            Default = @("claude-code", "codex", "my-app")
            Work    = @("claude-code")
        }
    }
    AiHarnesses            = @{
        "my-app" = @{
            WSL          = $false
            Destinations = @(
                @{ Kind = "Skills"; Placement = "Copy"; Files = @("."); Path = "{User}\.my-app\skills" }
                @{ Kind = "Rules"; Placement = "File"; Files = @("RULES.md"); Path = "{User}\.my-app\RULES.md" }
            )
        }
    }
    BootstrapConfig        = @{
        Steps = @{
            AiArtifacts = $true
        }
    }
}
```

## Related

- [`Deploy-AiArtifacts` in the AI module reference](../../../modules/ai.md#deploy-aiartifacts) - parameters, usage and behaviour
- [AI Artifacts](../../../ai/artifacts.md) - the design: kinds, harnesses, hooks, WSL, migration
- [AI configuration guides](README.md) - every guide for this module
- [`Update-AiArtifacts`](Update-AiArtifacts.md) - fills the vendored source folders this function links
- [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md) - reads the same configuration
- [`List-AiArtifacts`](List-AiArtifacts.md) - lists and audits what this function deploys
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

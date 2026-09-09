# Resolve-AiSkillsConfig

Resolves the `AiSkills` configuration section into expanded paths (`Root`, `Harnesses`, `WSLHarnesses`) and the configured `Sources`, the one view of that section every AI skills function shares.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiSkills`](../../configuration-reference.md#ai-skills) | hashtable | `Root`, `Harnesses` defaults; `Sources = @{}` | The whole section: `Root` (skills root), `Harnesses` (Windows skills directories), `Sources` (upstreams). `{RepoRoot}`, `{User}` and `{AppData}` are expanded in `Root` and `Harnesses`. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | Derives `WSLHarnesses` from the `{User}` harness entries (`/home/<user>/...`). Empty yields none. |

## Decisions

1. Do the defaults need changing at all?
    - Options: Set `AiSkills.Root` or `AiSkills.Harnesses` only when the skills should live elsewhere or a harness should be added or dropped. `Sources` is configured on the [`Update-AiSkills`](Update-AiSkills.md) page.
    - Default: `{RepoRoot}\AI\Skills` and the Claude Code plus `.agents` directories; no sources.
    - More detail: [`AiSkills`](../../configuration-reference.md#ai-skills)
2. Should WSL harness paths be derived?
    - Options: Set `DefaultWSLUsername` to get `/home/<user>/<harness>` for every `{User}` entry; leave it empty for Windows only.
    - Default: Empty - no WSL harnesses.
    - More detail: [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiSkills` (only when changing the defaults)
2. Reload and confirm the merge landed

## Step 1: Set `AiSkills`

State only what differs from the defaults. `Harnesses` is an array and replaces wholesale.

```powershell
DefaultWSLUsername = "you"
AiSkills           = @{
    Root      = "{RepoRoot}\AI\Skills"
    Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the resolved section back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Resolve-AiSkillsConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-AiSkillsConfig
(Resolve-AiSkillsConfig).WSLHarnesses
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLUsername = "you"
    AiSkills           = @{
        Root      = "{RepoRoot}\AI\Skills"
        Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
    }
}
```

## Related

- [`Resolve-AiSkillsConfig` in the AI module reference](../../../modules/ai.md#resolve-aiskillsconfig) - parameters, usage and behaviour
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiSkills`](Deploy-AiSkills.md) - reads the same configuration
- [`Update-AiSkills`](Update-AiSkills.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

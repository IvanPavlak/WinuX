# Resolve-AiModsConfig

Resolves the `AiMods` configuration section into expanded paths (`Root`, `Harnesses`, `WSLHarnesses`), the configured `Sources`, and the Claude Code settings files (`SettingsPath`, `WSLSettingsPath`), the one view of that section every AI mods function shares.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMods`](../../configuration-reference.md#ai-mods) | hashtable | `Root`, `Harnesses` defaults; `Sources = @{}` | The whole section: `Root` (mods root), `Harnesses` (Windows mods directories), `Sources` (upstreams). `{RepoRoot}`, `{User}` and `{AppData}` are expanded in `Root` and `Harnesses`. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | Derives `WSLHarnesses` from the `{User}` harness entries (`/home/<user>/...`) and `WSLSettingsPath` (`/home/<user>/.claude/settings.json`). Empty yields neither. |

`SettingsPath` is always `~\.claude\settings.json` and is not configurable: it is the only user settings file Claude Code reads `CLAUDE_CODE_PLUGIN_DIRS` from.

## Decisions

1. Do the defaults need changing at all?
    - Options: Set `AiMods.Root` or `AiMods.Harnesses` only when the mods should live elsewhere or be linked somewhere else. `Sources` is configured on the [`Update-AiMods`](Update-AiMods.md) page.
    - Default: `{RepoRoot}\AI\Mods` and `{User}\.claude\mods`; no sources.
    - More detail: [`AiMods`](../../configuration-reference.md#ai-mods)
2. Should WSL paths be derived?
    - Options: Set `DefaultWSLUsername` to get `/home/<user>/<harness>` for every `{User}` entry plus the WSL settings file; leave it empty for Windows only.
    - Default: Empty - no WSL harnesses, no WSL settings file.
    - More detail: [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiMods.Root` and `AiMods.Harnesses` (only when changing the defaults)
2. Set `DefaultWSLUsername` for WSL
3. Reload and confirm the merge landed

## Step 1: Set `AiMods.Root` and `AiMods.Harnesses`

`Root` is a scalar and `Harnesses` an array; both replace wholesale.

```powershell
AiMods = @{
    Root      = "{RepoRoot}\AI\Mods"
    Harnesses = @("{User}\.claude\mods")
}
```

## Step 2: Set `DefaultWSLUsername`

The WSL account whose home directory the WSL paths are derived from.

```powershell
DefaultWSLUsername = "you"
```

## Step 3: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Resolve-AiModsConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-AiModsConfig).Root
(Resolve-AiModsConfig).Harnesses
(Resolve-AiModsConfig).WSLHarnesses
(Resolve-AiModsConfig).SettingsPath
(Resolve-AiModsConfig).WSLSettingsPath
```

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLUsername = "you"
    AiMods             = @{
        Root      = "{RepoRoot}\AI\Mods"
        Harnesses = @("{User}\.claude\mods")
        Sources   = @{
            "my-mod" = @{
                Repository = "MyOrg/MyMod"
                Ref        = "v1.0.0"
            }
        }
    }
}
```

## Related

- [`Resolve-AiModsConfig` in the AI module reference](../../../modules/ai.md#resolve-aimodsconfig) - parameters, usage and behaviour
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiMods`](Deploy-AiMods.md) - links the mods with these paths
- [`Update-AiMods`](Update-AiMods.md) - vendors the configured sources
- [`Get-AiModRoster`](Get-AiModRoster.md) - walks the resolved root
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

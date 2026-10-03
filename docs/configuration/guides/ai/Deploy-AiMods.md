# Deploy-AiMods

Links every Claude Code mod under the mods root into `~\.claude\mods`, one symbolic link per mod, and points Claude Code at them through the single key `env.CLAUDE_CODE_PLUGIN_DIRS` of `~\.claude\settings.json`, on Windows and inside WSL.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMods.Root`](../../configuration-reference.md#ai-mods) | string | `{RepoRoot}\AI\Mods` | The mods root: one subfolder per source, each holding `<mod>\.claude-plugin\plugin.json` folders. |
| [`AiMods.Harnesses`](../../configuration-reference.md#ai-mods) | array | `{User}\.claude\mods` | The Windows directories mods are linked into. The FIRST one is the directory `CLAUDE_CODE_PLUGIN_DIRS` lists; the `{User}` entries also yield the WSL twins under `/home/<DefaultWSLUsername>/`. |
| [`BootstrapConfig.Steps.AiMods`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. OFF by default - the base ships no mods. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution the WSL links are created in and whose `\\wsl.localhost` share carries the WSL settings file. Empty means no WSL links. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL account whose home directory receives the links and whose `~/.claude/settings.json` is updated. Empty means no WSL links. |

The settings file itself is not a configuration key: it is always the user's `~\.claude\settings.json` (and `/home/<DefaultWSLUsername>/.claude/settings.json` in WSL), because that is the only file Claude Code reads `CLAUDE_CODE_PLUGIN_DIRS` from. Only that one key is written; every other setting is kept.

## Decisions

1. Where should the mods live in the repository?
    - Options: Any folder; `{RepoRoot}`, `{User}` and `{AppData}` placeholders are expanded. Vendored upstreams go in `<Root>\<source>\` (filled by `Update-AiMods`), hand-written mods in `<Root>\own\`.
    - Default: `{RepoRoot}\AI\Mods`.
    - More detail: [`AiMods.Root`](../../configuration-reference.md#ai-mods)
2. Which directory should the mods be linked into?
    - Options: Keep the one default directory, or name others; arrays replace wholesale on merge, and only the first directory is listed in `CLAUDE_CODE_PLUGIN_DIRS`, so no mod is loaded twice.
    - Default: `{User}\.claude\mods`.
    - More detail: [`AiMods.Harnesses`](../../configuration-reference.md#ai-mods)
3. Should Bootstrap deploy the mods on every run?
    - Options: `$true` to link (and self-heal) and refresh the settings key on every Bootstrap; `$false` to run `Deploy-AiMods` by hand.
    - Default: `$false` - a vanilla bootstrap deploys nothing.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)
4. Should the mods also reach Claude Code running inside WSL?
    - Options: Set both `DefaultWSLDistribution` and `DefaultWSLUsername`; leave either empty to deploy on Windows only.
    - Default: Empty - Windows only.
    - More detail: [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiMods.Root` and `AiMods.Harnesses` (only when changing the defaults)
2. Enable `BootstrapConfig.Steps.AiMods`
3. Set `DefaultWSLDistribution` and `DefaultWSLUsername` for WSL
4. Reload and confirm the merge landed

## Step 1: Set `AiMods.Root` and `AiMods.Harnesses`

Both default to sensible values; state them only to change them. `Harnesses` is an array, so list every directory, the one Claude Code should load from first.

```powershell
AiMods = @{
    Root      = "{RepoRoot}\AI\Mods"
    Harnesses = @("{User}\.claude\mods")
}
```

## Step 2: Enable `BootstrapConfig.Steps.AiMods`

With the step on, Bootstrap runs `Deploy-AiMods` right after `Deploy-AiSkills`, and every run self-heals the links and the settings key.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiMods = $true
    }
}
```

## Step 3: Set `DefaultWSLDistribution` and `DefaultWSLUsername`

The WSL links are created as this user inside this distribution, pointing at the `/mnt/<drive>` mount of the repository, and the user's WSL settings file is updated through `\\wsl.localhost\<distro>`. Leave either empty to skip WSL.

```powershell
DefaultWSLDistribution = "Ubuntu"
DefaultWSLUsername     = "you"
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged values back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Resolve-AiModsConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-AiModsConfig
Resolve-BootstrapSteps | Where-Object Name -eq "AiMods"
Get-ChildItem "$env:USERPROFILE\.claude\mods" | Select-Object Name, LinkTarget
(Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS
claude plugin validate "$env:USERPROFILE\.claude\mods\my-mod"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    DefaultWSLUsername     = "you"
    AiMods                 = @{
        Root      = "{RepoRoot}\AI\Mods"
        Harnesses = @("{User}\.claude\mods")
    }
    BootstrapConfig        = @{
        Steps = @{
            AiMods = $true
        }
    }
}
```

## Related

- [`Deploy-AiMods` in the AI module reference](../../../modules/ai.md#deploy-aimods) - parameters, usage and behaviour
- [AI Mods](../../../ai/mods.md) - the design: why one link per mod plus one settings key, harness table, verification
- [AI configuration guides](README.md) - every guide for this module
- [`Update-AiMods`](Update-AiMods.md) - fills the source folders this function links
- [`Resolve-AiModsConfig`](Resolve-AiModsConfig.md) - reads the same configuration
- [`Configure-WSL`](../system/Configure-WSL.md) - reads the same WSL configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

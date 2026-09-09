# Deploy-AiSkills

Links every skill under the skills root into each AI harness's user-level skills directory (Claude Code, Codex CLI, Gemini CLI), one symbolic link per skill, on Windows and inside WSL.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiSkills.Root`](../../configuration-reference.md#ai-skills) | string | `{RepoRoot}\AI\Skills` | The skills root: one subfolder per source, each holding flat `<skill>\SKILL.md` folders. |
| [`AiSkills.Harnesses`](../../configuration-reference.md#ai-skills) | array | `{User}\.claude\skills`, `{User}\.agents\skills` | The Windows directories skills are linked into. The `{User}` entries also yield the WSL twins under `/home/<DefaultWSLUsername>/`. |
| [`BootstrapConfig.Steps.AiSkills`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. OFF by default - the base ships no skills. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution the WSL links are created in. Empty means no WSL links. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL account whose home directory receives the links. Empty means no WSL links. |

## Decisions

1. Where should the skills live in the repository?
    - Options: Any folder; `{RepoRoot}`, `{User}` and `{AppData}` placeholders are expanded. Vendored upstreams go in `<Root>\<source>\` (filled by `Update-AiSkills`), hand-written skills in `<Root>\own\`.
    - Default: `{RepoRoot}\AI\Skills`.
    - More detail: [`AiSkills.Root`](../../configuration-reference.md#ai-skills)
2. Which harnesses should see the skills?
    - Options: Any list of directories a harness scans for user-level skills. Claude Code reads `~\.claude\skills`; Codex CLI and Gemini CLI read `~\.agents\skills`. Arrays replace wholesale on merge, so name every directory you want.
    - Default: Both of those.
    - More detail: [`AiSkills.Harnesses`](../../configuration-reference.md#ai-skills)
3. Should Bootstrap link the skills on every run?
    - Options: `$true` to link (and self-heal) on every Bootstrap; `$false` to run `Deploy-AiSkills` by hand.
    - Default: `$false` - a vanilla bootstrap links nothing.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)
4. Should the skills also reach harnesses running inside WSL?
    - Options: Set both `DefaultWSLDistribution` and `DefaultWSLUsername`; leave either empty to link on Windows only.
    - Default: Empty - Windows only.
    - More detail: [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiSkills.Root` and `AiSkills.Harnesses` (only when changing the defaults)
2. Enable `BootstrapConfig.Steps.AiSkills`
3. Set `DefaultWSLDistribution` and `DefaultWSLUsername` for WSL
4. Reload and confirm the merge landed

## Step 1: Set `AiSkills.Root` and `AiSkills.Harnesses`

Both default to sensible values; state them only to change them. `Harnesses` is an array, so list every directory.

```powershell
AiSkills = @{
    Root      = "{RepoRoot}\AI\Skills"
    Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
}
```

## Step 2: Enable `BootstrapConfig.Steps.AiSkills`

With the step on, Bootstrap runs `Deploy-AiSkills` right after `Deploy-CoreAiRules`, and every run self-heals the links.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiSkills = $true
    }
}
```

## Step 3: Set `DefaultWSLDistribution` and `DefaultWSLUsername`

The WSL links are created as this user inside this distribution, pointing at the `/mnt/<drive>` mount of the repository. Leave either empty to skip WSL.

```powershell
DefaultWSLDistribution = "Ubuntu"
DefaultWSLUsername     = "you"
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged values back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Resolve-AiSkillsConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-AiSkillsConfig
Resolve-BootstrapSteps | Where-Object Name -eq "AiSkills"
Get-ChildItem "$env:USERPROFILE\.claude\skills" | Select-Object Name, LinkTarget
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    DefaultWSLUsername     = "you"
    AiSkills               = @{
        Root      = "{RepoRoot}\AI\Skills"
        Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
    }
    BootstrapConfig        = @{
        Steps = @{
            AiSkills = $true
        }
    }
}
```

## Related

- [`Deploy-AiSkills` in the AI module reference](../../../modules/ai.md#deploy-aiskills) - parameters, usage and behaviour
- [AI Skills](../../../ai/skills.md) - the design: why one link per skill, harness table, verification
- [AI configuration guides](README.md) - every guide for this module
- [`Update-AiSkills`](Update-AiSkills.md) - fills the source folders this function links
- [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md) - reads the same configuration
- [`Configure-WSL`](../system/Configure-WSL.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

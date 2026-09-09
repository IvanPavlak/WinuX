# Update-AiSkills

Vendors Agent Skills from the configured upstream repositories into the skills root, flat and pinned to an exact commit, and records provenance in `UPSTREAM.md` per source.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiSkills.Root`](../../configuration-reference.md#ai-skills) | string | `{RepoRoot}\AI\Skills` | Where each source is vendored: `<Root>\<source>\`. |
| [`AiSkills.Sources`](../../configuration-reference.md#ai-skills) | hashtable | `@{}` (empty) | One entry per upstream: `Repository` (`owner/name`), `Ref` (branch, tag or commit; default `main`), `Folders` (upstream folders whose skill subfolders are flattened; default `skills`), `Exclude` (skill names to leave out). Empty means the function no-ops. |

## Decisions

1. Which upstream skill repositories should be vendored?
    - Options: Any GitHub repository whose skills are folders holding a `SKILL.md`; one `Sources` entry per repository, keyed by the folder name you want under the skills root.
    - Default: None - the base ships no sources and `Update-AiSkills` does nothing.
    - More detail: [`AiSkills.Sources`](../../configuration-reference.md#ai-skills)
2. Which ref should each source track?
    - Options: A branch (`main`) to pick up the current head on every refresh, or a tag or commit sha to pin. `UPSTREAM.md` always records the exact commit the ref resolved to.
    - Default: `main`.
    - More detail: [`AiSkills.Sources`](../../configuration-reference.md#ai-skills)
3. Which upstream folders hold the skills, and which skills should be left out?
    - Options: `Folders` lists the upstream directories to scan (forward slashes, e.g. `skills/engineering`); `Exclude` names skills to skip, for example a `code-review` that would replace Claude Code's built-in `/code-review`.
    - Default: `Folders = @("skills")`, `Exclude = @()`.
    - More detail: [`AiSkills.Sources`](../../configuration-reference.md#ai-skills)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiSkills.Sources`
2. Reload and confirm the merge landed

## Step 1: Set `AiSkills.Sources`

One entry per upstream. The key becomes the folder name under the skills root.

```powershell
AiSkills = @{
    Sources = @{
        mattpocock = @{
            Repository = "mattpocock/skills"
            Ref        = "main"
            Folders    = @("skills/engineering", "skills/productivity")
            Exclude    = @()
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
(Resolve-AiSkillsConfig).Sources
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
(Resolve-AiSkillsConfig).Sources
Update-AiSkills -Check
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiSkills = @{
        Root    = "{RepoRoot}\AI\Skills"
        Sources = @{
            mattpocock = @{
                Repository = "mattpocock/skills"
                Ref        = "main"
                Folders    = @("skills/engineering", "skills/productivity")
                Exclude    = @("code-review")
            }
        }
    }
}
```

## Related

- [`Update-AiSkills` in the AI module reference](../../../modules/ai.md#update-aiskills) - parameters, usage and behaviour
- [AI Skills](../../../ai/skills.md) - the design, including name collisions with built-in skills
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiSkills`](Deploy-AiSkills.md) - links what this function vendors into the harnesses
- [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

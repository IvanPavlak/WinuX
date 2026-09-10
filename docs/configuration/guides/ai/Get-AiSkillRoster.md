# Get-AiSkillRoster

Walks the skills root and returns the flattened roster - skill name to path and source - that both `Deploy-AiSkills` and `List-Skills` work from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiSkills.Root`](../../configuration-reference.md#ai-skills) | string | `{RepoRoot}\AI\Skills` | The folder walked when `-Root` is not supplied. Read through [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md), so `{RepoRoot}`, `{User}` and `{AppData}` are expanded. |

Nothing else. The roster is a reading of the disk, not of the configuration: what counts as a skill (`<source>\<skill>\SKILL.md`) and how a name collision is resolved (first source alphabetically) are fixed rules, not settings, because `Deploy-AiSkills` links by exactly those rules and a configurable disagreement between the two would mean listing one thing and deploying another.

## Decisions

1. Where do the skills live?
    - Options: Leave `AiSkills.Root` at the default so the roster comes from the repository, or point it elsewhere if your skills are not kept in the repo.
    - Default: `{RepoRoot}\AI\Skills`, one subfolder per source.
    - More detail: [`AiSkills`](../../configuration-reference.md#ai-skills)
2. Do you need to configure this function at all?
    - Options: In practice no - configure `AiSkills` once on the [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md) or [`Deploy-AiSkills`](Deploy-AiSkills.md) page and every reader of the section follows, this one included. Pass `-Root` for a one-off walk of a different tree.
    - Default: The resolved `AiSkills.Root`.

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiSkills.Root` (only when the skills do not live in the repository)
2. Reload and confirm the roster reads back

## Step 1: Set `AiSkills.Root`

Only when the default does not fit. `Root` is a scalar and replaces wholesale.

```powershell
AiSkills = @{
    Root = "{RepoRoot}\AI\Skills"
}
```

## Step 2: Reload and confirm the roster reads back

```powershell
Reload-PowerShellProfile
(Get-AiSkillRoster).Root
(Get-AiSkillRoster).Skills.Count
```

An empty roster on a repository that does carry skills nearly always means `Root` points at the wrong folder, or that the folders under it hold no `SKILL.md`.

## Verification

Read-only checks. None of these change anything.

```powershell
(Get-AiSkillRoster).Skills.Keys
(Get-AiSkillRoster).Duplicates
Get-AiSkillRoster -Root "C:\Repo\AI\Skills"
```

A non-empty `Duplicates` list means two sources carry the same skill name; the entry names which source won. `List-Skills -ListDiscrepancies` reports the same collision in prose.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiSkills = @{
        Root = "{RepoRoot}\AI\Skills"
    }
}
```

## Related

- [`Get-AiSkillRoster` in the AI module reference](../../../modules/ai.md#get-aiskillroster) - parameters, usage and behaviour
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiSkills`](Deploy-AiSkills.md) - links the skills this roster lists
- [`List-Skills`](List-Skills.md) - displays and audits the same roster
- [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md) - where `AiSkills.Root` is actually configured
- [Configuration reference](../../configuration-reference.md) - every key, section by section

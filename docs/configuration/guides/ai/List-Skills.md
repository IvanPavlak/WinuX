# List-Skills

Lists the Agent Skills the repository carries, grouped by source, and with `-ListDiscrepancies` audits them against the links actually present in the harness directories.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiSkills.Root`](../../configuration-reference.md#ai-skills) | string | `{RepoRoot}\AI\Skills` | The folder the roster is read from, through [`Resolve-AiSkillsConfig`](Resolve-AiSkillsConfig.md). |
| [`AiSkills.Harnesses`](../../configuration-reference.md#ai-skills) | string[] | `{User}\.claude\skills`, `{User}\.agents\skills` | The directories `-ListDiscrepancies` audits. Each is checked for a link per skill. |
| [`ShowFunctionDetailsColors`](../../configuration-reference.md#more-sections-quick-reference) | hashtable | `FunctionName`, `Description`, `Parameters` | Read indirectly: each skill is drawn by `Show-FunctionDetails`, the same renderer `List-Functions` uses, so retuning this palette retunes both catalogs at once. |

`AiSkills.WSLHarnesses` is deliberately *not* read: auditing it means shelling into the distribution, which is too slow for a listing. Run [`Deploy-AiSkills`](Deploy-AiSkills.md) to reconcile the WSL links; the report says so when it finds anything.

There is no colour key of its own, and nothing here formats output itself. Entries go through `Show-FunctionDetails`, group and total borders through `Create-CenteredBorder`, and every line this function emits on its own account through the Logging module, so it is mirrored into the session log and the borders take the shared [`Logging.Colors`](../../configuration-reference.md#more-sections-quick-reference) Title colour.

## Decisions

1. Which harnesses should the audit cover?
    - Options: Leave `AiSkills.Harnesses` at the default to audit Claude Code and the shared `.agents` directory, or list exactly the directories you deploy to. This is the same array `Deploy-AiSkills` links into, so the two always agree.
    - Default: `{User}\.claude\skills` and `{User}\.agents\skills`.
    - More detail: [`AiSkills`](../../configuration-reference.md#ai-skills)
2. Do the colors need changing?
    - Options: Nothing to set here on its own. Entries take `ShowFunctionDetailsColors` (shared with `List-Functions`) and the borders and messages take `Logging.Colors`, so either change affects more than this command.
    - Default: The shipped `ShowFunctionDetailsColors` and `Logging.Colors`.
    - More detail: [`ShowFunctionDetailsColors`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiSkills` (only when changing the defaults)
2. Reload and list what the machine carries

## Step 1: Set `AiSkills`

State only what differs from the defaults. `Harnesses` is an array and replaces wholesale, so copy the whole base array before adding to it.

```powershell
AiSkills = @{
    Root      = "{RepoRoot}\AI\Skills"
    Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
}
```

## Step 2: Reload and list what the machine carries

```powershell
Reload-PowerShellProfile
List-Skills
List-Skills -ListDiscrepancies
```

## Verification

Read-only checks. None of these change anything, including the audit - it reports what to fix and never links or unlinks.

```powershell
List-Skills
List-Skills -Source own
List-Skills -ListDiscrepancies
```

A clean audit says every skill is linked into every harness. "Present but NOT linked" almost always means a skill was added and `Deploy-AiSkills` was never re-run. A "links to" finding means something else owns that name in the harness. A stale link means a skill was removed or renamed; `Deploy-AiSkills` prunes those on its next run.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiSkills = @{
        Root      = "{RepoRoot}\AI\Skills"
        Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
    }
}
```

## Related

- [`List-Skills` in the AI module reference](../../../modules/ai.md#list-skills) - parameters, usage and behaviour
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiSkills`](Deploy-AiSkills.md) - creates the links this audits, WSL included
- [`Get-AiSkillRoster`](Get-AiSkillRoster.md) - the shared roster walk behind both
- [AI Skills](../../../ai/skills.md) - how the whole mechanism fits together
- [Configuration reference](../../configuration-reference.md) - every key, section by section

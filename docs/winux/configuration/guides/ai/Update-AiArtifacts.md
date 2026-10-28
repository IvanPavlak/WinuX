# Update-AiArtifacts

Vendors AI skills, mods, rules, prompts and agents from the upstream repositories in `AiArtifacts.Sources` into `<Root>\<Kind>\<source>\`, pinned to a commit.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiArtifacts.Sources`](../../configuration-reference.md#ai-artifacts) | hashtable | `@{}` (empty) | One entry per upstream: `Repository` (`owner/name`), `Ref` (default `main`), per kind the upstream folders (`Skills`, `Mods`, `Rules`, `Prompts`, `Agents`; none: `Skills = @("skills")`), `Exclude` (items not to vendor), `SkipPaths` (top-level entries of an item not to copy). |
| [`AiArtifacts.Root`](../../configuration-reference.md#ai-artifacts) | string | `{RepoRoot}\AI` | Where the vendored source folders are written. |

## Decisions

1. Which upstream repositories should be vendored?
    - Options: One `Sources` entry per GitHub repository, named by the folder it gets under each kind (`AI\Skills\<name>\`). One entry can feed several kinds.
    - Default: None - the base vendors nothing.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)
2. Which commit should a source follow?
    - Options: A branch (moves on every refresh), a tag or a commit sha in `Ref`. `UPSTREAM.md` always records the exact commit resolved.
    - Default: `main`.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)
3. Which upstream items should stay out?
    - Options: Item names in the entry's `Exclude`; top-level entries of each item in `SkipPaths`. To keep an item vendored but not deployed, use `AiArtifacts.Exclude` instead.
    - Default: Nothing excluded; `.git`, `.github`, `tests`, `design`, `docs` skipped.
    - More detail: [`AiArtifacts`](../../configuration-reference.md#ai-artifacts)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Add a `Sources` entry
2. Vendor it and review the diff
3. Reload and confirm the merge landed

## Step 1: Add a `Sources` entry

```powershell
AiArtifacts = @{
    Sources = @{
        mattpocock = @{
            Repository = "OWNER/skills"
            Ref        = "main"
            Skills     = @("skills/engineering", "skills/productivity")
            Exclude    = @()
        }
    }
}
```

A private repository needs a GitHub token: `GITHUB_TOKEN`, `GH_TOKEN`, or a signed-in GitHub CLI (`gh auth login`).

## Step 2: Vendor it and review the diff

```powershell
Update-AiArtifacts -Source mattpocock
git status -- AI
```

Commit the vendored folders like any other file; a fresh machine then needs only `Deploy-AiArtifacts`.

## Step 3: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
(Resolve-AiArtifactsConfig).Sources
```

## Verification

Read-only checks. None of these change anything.

```powershell
Update-AiArtifacts -Check
Get-AiSkillManifest -Path (Join-Path (Resolve-AiArtifactsConfig).Root "Skills\mattpocock\UPSTREAM.md")
```

`-Check` reports per source and kind whether the vendored copy is behind its `Ref`.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiArtifacts = @{
        Sources = @{
            mattpocock = @{
                Repository = "OWNER/skills"
                Ref        = "main"
                Skills     = @("skills/engineering")
                Exclude    = @("tdd")
            }
            "my-mod"   = @{
                Repository = "MyOrg/MyMod"
                Ref        = "v1.0.0"
                Mods       = @(".")
                SkipPaths  = @(".git", ".github", "tests")
            }
        }
    }
}
```

## Related

- [`Update-AiArtifacts` in the AI module reference](../../../modules/ai.md#update-aiartifacts) - parameters, usage and behaviour
- [AI Artifacts - Vendoring](../../../ai/artifacts.md#vendoring) - the design
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) - links what this function vendors
- [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

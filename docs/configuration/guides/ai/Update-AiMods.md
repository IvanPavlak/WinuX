# Update-AiMods

Vendors Claude Code mods from the configured upstream repositories into the mods root, pinned to an exact commit, without the paths a mod keeps upstream (tests, design assets, CI), and records provenance in `UPSTREAM.md` per source.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMods.Root`](../../configuration-reference.md#ai-mods) | string | `{RepoRoot}\AI\Mods` | Where each source is vendored: `<Root>\<source>\<mod>\`. |
| [`AiMods.Sources`](../../configuration-reference.md#ai-mods) | hashtable | `@{}` (empty) | One entry per upstream: `Repository` (`owner/name`), `Ref` (branch, tag or commit; default `main`), `Folders` (upstream folders holding mods; `.` is the repository root; default `.`), `Exclude` (mod names to leave out), `SkipPaths` (top-level entries of a mod not to copy; default `.git`, `.github`, `tests`, `design`, `docs`). Empty means the function no-ops. |

## Decisions

1. Which upstream mod repositories should be vendored?
    - Options: Any GitHub repository holding Claude Code mods (folders with `.claude-plugin\plugin.json`); one `Sources` entry per repository, keyed by the folder name you want under the mods root.
    - Default: None - the base ships no sources and `Update-AiMods` does nothing.
    - More detail: [`AiMods.Sources`](../../configuration-reference.md#ai-mods)
2. Which ref should each source track?
    - Options: A release tag (`v1.0.0`) to pin a known-good version, a branch (`main`) to pick up the current head on every refresh, or a commit sha. `UPSTREAM.md` always records the exact commit the ref resolved to.
    - Default: `main`.
    - More detail: [`AiMods.Sources`](../../configuration-reference.md#ai-mods)
3. Where are the mods in the upstream repository, and which should be left out?
    - Options: `Folders = @(".")` when the repository root is the mod; otherwise the folders whose subfolders are mods. `Exclude` names mods (by their `plugin.json` name) to skip.
    - Default: `Folders = @(".")`, `Exclude = @()`.
    - More detail: [`AiMods.Sources`](../../configuration-reference.md#ai-mods)
4. Which parts of a mod should stay upstream?
    - Options: `SkipPaths` lists top-level entries of each mod that are not copied; an empty array copies everything. Only what Claude Code loads needs vendoring.
    - Default: `.git`, `.github`, `tests`, `design`, `docs`.
    - More detail: [`AiMods.Sources`](../../configuration-reference.md#ai-mods)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `AiMods.Sources`
2. Reload and confirm the merge landed

## Step 1: Set `AiMods.Sources`

One entry per upstream. The key becomes the folder name under the mods root; each mod inside it is named by its `plugin.json`.

```powershell
AiMods = @{
    Sources = @{
        "my-mod" = @{
            Repository = "MyOrg/MyMod"
            Ref        = "v1.0.0"
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged sources back and compare each pinned commit with its upstream without downloading anything.

```powershell
Reload-PowerShellProfile
(Resolve-AiModsConfig).Sources
Update-AiMods -Check
```

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-AiModsConfig).Sources
Update-AiMods -Check
Get-Content "C:\Users\You\Development\MyRepo\AI\Mods\my-mod\UPSTREAM.md"
```

`-Check` reports each source as up to date, behind its upstream ref, or not vendored yet. Run `Update-AiMods` (or `Update-AiMods -Source my-mod`) to refresh, review the diff, then `Deploy-AiMods` to link.

## Private Repositories

A source can be a private repository. `Update-AiMods` looks for a GitHub token in `GITHUB_TOKEN`, then `GH_TOKEN`, then `gh auth token` when the GitHub CLI is installed and signed in, and with one it authenticates both the commit lookup and the download (through the API's zipball endpoint). The token is sent only to `api.github.com` and never logged; nothing about it goes into `Configuration.local.psd1`. With the GitHub CLI signed in to an account that can read the repository, nothing else is needed:

```powershell
gh auth status
Update-AiMods -Check
```

Without a token a private repository answers 404, and the error names both ways to authenticate. A token for this needs read access to the repository's contents (the classic `repo` scope, or a fine-grained token with Contents: read).

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AiMods = @{
        Root    = "{RepoRoot}\AI\Mods"
        Sources = @{
            "my-mod" = @{
                Repository = "MyOrg/MyMod"
                Ref        = "v1.0.0"
                Folders    = @(".")
                Exclude    = @()
                SkipPaths  = @(".git", ".github", "tests", "design", "docs")
            }
        }
    }
}
```

## Related

- [`Update-AiMods` in the AI module reference](../../../modules/ai.md#update-aimods) - parameters, usage and behaviour
- [AI Mods](../../../ai/mods.md) - vendoring, pinning and deployment end to end
- [AI configuration guides](README.md) - every guide for this module
- [`Deploy-AiMods`](Deploy-AiMods.md) - links what this function vendors
- [`Update-AiSkills`](Update-AiSkills.md) - the same vendoring for Agent Skills
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

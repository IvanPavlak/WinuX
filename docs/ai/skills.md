# AI Skills

Machine-global Agent Skills: one set of `SKILL.md` skills kept in the repository and linked into every AI coding harness on the machine, so they are available in every project without adding anything to any project. The skills counterpart of [CoreAiRules](coreairules.md), which does the same for the rules file.

AI Skills is **opt-in**: the mechanism ships with WinuX, but the base configuration names no skill sources and `BootstrapConfig.Steps.AiSkills` is OFF, so a vanilla bootstrap links nothing.

## Design

Every harness discovers user-level skills from one flat directory of `<skill>/SKILL.md` and none recurses into subfolders:

| Harness     | User-level skills directory                                  |
| ----------- | ------------------------------------------------------------ |
| Claude Code | `~/.claude/skills/<skill>/SKILL.md`                          |
| Codex CLI   | `~/.agents/skills/<skill>/SKILL.md`                          |
| Gemini CLI  | `~/.agents/skills` (alias that wins over `~/.gemini/skills`) |

The repository keeps skills under `AI/Skills/<source>/<skill>/` - one subfolder per source, so a vendored upstream (say `mattpocock`) and your own skills (`own`) never mix - and [Deploy-AiSkills](../modules/ai.md#deploy-aiskills) links each skill individually into every harness directory, on Windows and inside WSL. Linking per skill rather than linking the whole root is what lets the per-source layout coexist with the harnesses' flat requirement, keeps the harness directories machine-local (skills installed by other tools sit next to the linked ones), and lets a deleted skill disappear on the next run: dangling links into the skills root are pruned, links to anything else are never touched.

[Update-AiSkills](../modules/ai.md#update-aiskills) fills the vendored source folders from GitHub: it resolves the configured ref to an exact commit, downloads that commit's archive, flattens the upstream's category folders, and records provenance in `AI/Skills/<source>/UPSTREAM.md` (pinned commit, folders, exclusions, a table of every skill with its description) next to a copy of the upstream license. It removes only what the previous manifest lists, so a folder you add by hand inside a source survives a refresh, and `-Check` reports whether a source is behind upstream without writing anything. It is a manual command, not a Bootstrap step: the vendored tree is committed, so a fresh machine only needs `Deploy-AiSkills`.

Upstream ships only `AI/Skills/README.md`. The source folders are yours - a fork adds them, and upstream never writes there.

## Configuration

```powershell
# Configuration.local.psd1
@{
    AiSkills = @{
        # Where the skills live; one subfolder per source.
        Root      = "{RepoRoot}\AI\Skills"
        # Harness skills directories to link into. WSL twins are derived from the {User}
        # entries and DefaultWSLUsername (/home/<user>/.claude/skills, ...).
        Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
        # Upstreams vendored by Update-AiSkills into Root\<name>\.
        Sources   = @{
            mattpocock = @{
                Repository = "mattpocock/skills"                              # owner/name
                Ref        = "main"                                           # branch, tag or commit
                Folders    = @("skills/engineering", "skills/productivity")   # upstream folders whose skill subfolders are flattened
                Exclude    = @()                                              # skill names to leave out
            }
        }
    }
    BootstrapConfig = @{
        Steps = @{
            AiSkills = $true
        }
    }
}
```

`Root` and `Harnesses` only need stating when you change them; the values above are the defaults. Arrays replace wholesale on merge, so a `Harnesses` override names every directory you want.

## Name collisions

A personal skill replaces a bundled skill of the same name in Claude Code, so vendoring an upstream `code-review` hides Claude Code's built-in `/code-review`. Leave such a skill out with `Exclude` if you want the built-in one, or accept the replacement. Within the repository, the same skill name under two sources is reported and the first source by name wins.

## Verification (per machine, after enabling)

1. Run `Update-AiSkills` once (or pull a repository that already carries the vendored folders), review the diff, then run `Deploy-AiSkills` (or full `Bootstrap`) as admin.
2. Check that `~/.claude/skills/<skill>` and `~/.agents/skills/<skill>` are symbolic links into `AI/Skills/<source>/`, and inside WSL that `/home/<user>/.claude/skills/<skill>` resolves through `/mnt/<drive>`.
3. In a throwaway folder outside the repository, start the harness and confirm the skills appear (`/` in Claude Code, `/skills` in Codex CLI, `gemini skills list`).

## Related

- [AI module reference](../modules/ai.md) - `Deploy-AiSkills`, `Update-AiSkills`, `Resolve-AiSkillsConfig`, `Get-AiSkillManifest`, `Get-AiSkillDescription`
- [Deploy-AiSkills configuration guide](../configuration/guides/ai/Deploy-AiSkills.md) - the `AiSkills` keys, decision by decision
- [CoreAiRules](coreairules.md) - the rules file that sits in front of the same harnesses

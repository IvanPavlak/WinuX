# AI Artifacts

How WinuX deploys the AI artifacts - the skills, mods, rules, prompts and agents - into the AI apps a machine uses, on Windows and inside WSL. WinuX ships the mechanism and its own product skills; which artifacts a machine gets, and into which apps, is the fork's choice, configured in `Configuration.local.psd1` like everything else.

The kind specifics are on their own pages: [AI Skills](skills.md), [AI Mods](mods.md) and [CoreAiRules](coreairules.md) (the rules). The commands are on the [AI module page](../modules/ai.md).

## Artifacts

An artifact is a folder under the artifacts root (`AiArtifacts.Root`, default `{RepoRoot}\AI`), kind first: `AI\<Kind>\<source>\<item>\`.

| Kind | Folder | An item is a folder holding | Portable file |
| ---- | ------ | --------------------------- | ------------- |
| Skills | `AI\Skills` | `SKILL.md` | `SKILL.md` |
| Mods | `AI\Mods` | `.claude-plugin\plugin.json` (a Claude Code mod) | - |
| Rules | `AI\Rules` | at least one file (its variants) | `RULES.md` |
| Prompts | `AI\Prompts` | at least one file | `PROMPT.md` |
| Agents | `AI\Agents` | at least one file | `AGENT.md` |

Formats are never translated: an item is linked as it is. An item folder may carry one file per app (`claude.md`, `codex.toml`, `copilot.agent.md`, Claude Code's `managed-settings.json`), and each destination of an app names the files it takes, in order; the portable file is the fallback.

The sources read, in this order, the first winning an item name two of them carry (with a warning):

1. `own` - your own items, never touched by a refresh. WinuX ships it empty.
2. Then, in name order: `winux` (the product skills WinuX ships: [winux-configurator](../configuration/winux-configurator.md) and `document`, which turns a function's comment-based help into its module page entry and configuration guide), `example` (the example rules) and every vendored source, an `AiArtifacts.Sources` entry filled by [Update-AiArtifacts](../modules/ai.md#update-aiartifacts).

Any other source folder is not read. Leave an item out with an `AiArtifacts.Exclude` entry: `"skills/tdd"` drops it from every source, `"skills/winux/document"` from one, and `@{ Item = "skills/tdd"; Machine = "Work" }` on one machine type.

Prompts and agents ship no items: they are kinds a fork fills, under `AI\Prompts\own\` and `AI\Agents\own\` or from a vendored source.

## Harnesses

A harness is an app Deploy-AiArtifacts can deploy into, one entry of `AiHarnesses`. The base catalogue is inactive: `AiArtifacts.Deploy` turns harnesses on per machine type, `Default` covering every type without its own key.

```powershell
AiArtifacts = @{
    Deploy = @{
        Default = @("claude-code", "codex")
        Work    = @("claude-code")
    }
}
```

Each harness has `WSL` (`$true`: WSL twins, below) and `Destinations`, one hashtable per destination:

| Key | Meaning |
| --- | ------- |
| `Kind` | `Skills`, `Mods`, `Rules`, `Prompts` or `Agents` |
| `Placement` | `Each`: `Path` is a folder, one link per item; `Copy`: the same, copied (for an app that does not follow links), a copy that differs from the repository's is replaced; `File`: `Path` is one file, linked to the item `AiArtifacts.Use` names for the kind |
| `Files` | the first one the item has: `.` is the item folder itself (linked as `<item>`), a file name is that file (linked as `<item>` plus the file's extension: `claude.md` as `<item>.md`, `copilot.agent.md` as `<item>.agent.md`); an item with none of them is left out of this destination |
| `Hooks` | `claude-plugin-dirs`: sets `env.CLAUDE_CODE_PLUGIN_DIRS` of `~\.claude\settings.json` to the links, **joined with `;`** (`:` in WSL), then every entry added by hand, and runs `claude plugin validate` on each (a missing or rejecting CLI only warns); `managed-settings`: the WSL twin is made as root |
| `Path` | the Windows destination; `{User}`, `{RepoRoot}` and `{AppData}` expand |
| `WSLPath` | the WSL twin, when it is not derived from a `{User}` path |
| `Machine` | optional machine scope (`"PC/Work"`); absent means every machine type |

A destination two harnesses name (Codex, Gemini CLI and Copilot all read `~\.agents\skills`) is filled once. A destination no item goes to is never created. A fork defines any other app with an entry of its own; a same-named entry deep-merges, but its `Destinations` array replaces the base list wholesale.

### The base catalogue

Each folder was checked against the app's own documentation (2026-10-25); the sources are listed below the table.

| Harness | Kind | Placement, files | Windows path | WSL twin |
| ------- | ---- | ---------------- | ------------ | -------- |
| `claude-code` | Skills | Each, `.` | `{User}\.claude\skills` | `~/.claude/skills` |
| | Mods | Each, `.`, `claude-plugin-dirs` | `{User}\.claude\mods` | `~/.claude/mods` |
| | Rules | File, `RULES.md` | `{User}\.claude\CLAUDE.md` | `~/.claude/CLAUDE.md` |
| | Rules | File, `managed-settings.json`, `managed-settings` | `C:\Program Files\ClaudeCode\managed-settings.json` | `/etc/claude-code/managed-settings.json` |
| | Prompts | Each, `claude.md`, `PROMPT.md` | `{User}\.claude\commands` | `~/.claude/commands` |
| | Agents | Each, `claude.md`, `AGENT.md` | `{User}\.claude\agents` | `~/.claude/agents` |
| `codex` | Skills | Each, `.` | `{User}\.agents\skills` | `~/.agents/skills` |
| | Rules | File, `RULES.md` | `{User}\.codex\AGENTS.md` | `~/.codex/AGENTS.md` |
| | Prompts | Each, `codex.md`, `PROMPT.md` | `{User}\.codex\prompts` | `~/.codex/prompts` |
| | Agents | Each, `codex.toml` | `{User}\.codex\agents` | `~/.codex/agents` |
| `gemini-cli` | Skills | Each, `.` | `{User}\.agents\skills` | `~/.agents/skills` |
| | Rules | File, `RULES.md` | `{User}\.gemini\GEMINI.md` | `~/.gemini/GEMINI.md` |
| | Prompts | Each, `gemini.toml` | `{User}\.gemini\commands` | `~/.gemini/commands` |
| | Agents | Each, `gemini.md`, `AGENT.md` | `{User}\.gemini\agents` | `~/.gemini/agents` |
| `copilot` | Skills | Each, `.` | `{User}\.agents\skills` | `~/.agents/skills` |
| | Rules | File, `copilot.md`, `RULES.md` | `{User}\.copilot\copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| | Agents | Each, `copilot.agent.md` | `{User}\.copilot\agents` | `~/.copilot/agents` |

- Claude Code's managed settings on Windows are read from `C:\Program Files\ClaudeCode\managed-settings.json`. Claude Code no longer reads the legacy `C:\ProgramData\ClaudeCode\managed-settings.json`, so a link there (the 1.5 `SymbolicLinks` example) has no effect. In WSL they are `/etc/claude-code/managed-settings.json`.
- Claude Code's `~\.claude\commands` still works, but its documentation now merges custom commands into skills. Codex documents its custom prompts as deprecated in favour of skills.
- Codex agents are TOML and Gemini CLI commands are TOML: only an item carrying that variant reaches them.
- Copilot: the Copilot CLI's skill, instruction and agent folders. The CLI documents no prompt files, so the catalogue has no Copilot prompts. VS Code's Copilot also reads `~\.claude\skills` and `~\.agents\skills`, so with both `claude-code` and `copilot` on, it sees each skill twice.
- T3 Code has no entry: it drives the agents installed on the machine (Claude Code, Codex, ...), which read their own folders, so turning those on covers it.

Sources: Claude Code [skills](https://code.claude.com/docs/en/skills), [.claude directory](https://code.claude.com/docs/en/claude-directory), [managed settings](https://code.claude.com/docs/en/managed-settings) and [environment variables](https://code.claude.com/docs/en/env-vars); Codex [skills](https://learn.chatgpt.com/docs/build-skills), [custom prompts](https://learn.chatgpt.com/docs/custom-prompts), [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) and [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents); Gemini CLI [skills](https://geminicli.com/docs/cli/skills/), [custom commands](https://geminicli.com/docs/cli/custom-commands/), [subagents](https://geminicli.com/docs/core/subagents/) and [GEMINI.md](https://geminicli.com/docs/cli/gemini-md/); Copilot CLI [skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills), [custom agents](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli) and [custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions), VS Code [agent skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills); [T3 Code](https://github.com/pingdotgg/t3code).

### WSL twins

A harness with `WSL = $true` deploys every destination that has a WSL twin inside the default distribution too (`DefaultWSLDistribution`, as `DefaultWSLUsername`): a `{User}` path maps onto `/home/<DefaultWSLUsername>/`, any other path needs its own `WSLPath`. The links point at the `/mnt/<drive>` mount of the repository. Each destination is one `wsl -e sh <script>` call, run as the WSL user, or as root for a `managed-settings` destination (`/etc/claude-code` is root-owned). The `claude-plugin-dirs` hook updates the WSL user's `settings.json` from Windows through the `\\wsl.localhost\<distro>` share. Without a distribution or a username, nothing is deployed in WSL.

## Selection

Every item of every source read goes to every active app that accepts its kind, minus the `Exclude` entries. A `File` destination takes the one item `AiArtifacts.Use` names for its kind; without a `Use` entry it links nothing. A `Use` value may be per machine type:

```powershell
AiArtifacts = @{
    Use     = @{ Rules = @{ Default = "CoreAiRules"; Work = "WorkRules" } }
    Exclude = @("rules/example/CoreAiRules", @{ Item = "skills/tdd"; Machine = "Work" })
}
```

## Deploying

[Deploy-AiArtifacts](../modules/ai.md#deploy-aiartifacts) deploys, `-Kind` limits it to some kinds and `-WhatIf` reports what a run would change (`MISSING`, `WRONG`, `DIFFERS`, `STALE`) and changes nothing. It is the Bootstrap step `AiArtifacts`, off by default; `AiMarketplaces` (below) is its own step.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiArtifacts    = $true
        AiMarketplaces = $true
    }
}
```

Behaviour kept for every kind: a folder destination that is itself a link into the repository is replaced by a real folder, one that links elsewhere (or a file in its place) is skipped; a real file or folder where a link or copy goes is first copied into `Backups\Windows\SymbolicLinks\AiArtifacts.<kind>.<item>\<timestamp>\` (see [Backups](../reference/backups.md)), and when that copy fails the item is skipped; only dangling links that point into the artifacts root are pruned, a link to anything else is never touched. The run needs administrator rights (symbolic links and `C:\Program Files`), like `SymbolicLinkMaker`.

[List-AiArtifacts](../modules/ai.md#list-aiartifacts) lists what the repository carries, and `-ListDiscrepancies` checks every Windows destination against it.

## Vendoring

An `AiArtifacts.Sources` entry is one upstream repository, pinned to a commit, that can feed several kinds:

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

`Update-AiArtifacts` downloads the pinned archive and copies the items found under each kind's folders into `AI\<Kind>\<source>\`, writing an `UPSTREAM.md` per kind folder and the upstream license. A source without a kind key reads `Skills = @("skills")`; `SkipPaths` (default `.git`, `.github`, `tests`, `design`, `docs`) are top-level entries of an item not copied; a private repository needs a GitHub token (`GITHUB_TOKEN`, `GH_TOKEN` or a signed-in `gh`). The vendored tree is committed, so a fresh machine needs only `Deploy-AiArtifacts`.

## Marketplaces

Marketplaces are not an artifact kind: their plugins install through Claude Code's own CLI. [Deploy-AiMarketplaces](../modules/ai.md#deploy-aimarketplaces) reads `AiMarketplaces` and is the Bootstrap step `AiMarketplaces`; see [AI Mods - Marketplaces](mods.md#marketplaces). A plugin installed from a marketplace must not also be a mod in `AI\Mods`: Claude Code would load it twice.

## Verification (per machine, after enabling)

1. `Deploy-AiArtifacts -WhatIf` ends with a success line or names what is missing.
2. `List-AiArtifacts -ListDiscrepancies` reports nothing: every item is deployed into every destination of the harnesses turned on.
3. The rules: `(Get-Item ~\.claude\CLAUDE.md).LinkTarget` and `(Get-Item "C:\Program Files\ClaudeCode\managed-settings.json").LinkTarget` print paths inside `AI\Rules\`; in WSL, `readlink ~/.claude/CLAUDE.md /etc/claude-code/managed-settings.json` prints `/mnt/<drive>/...` paths.
4. The mods: `(Get-Content ~\.claude\settings.json | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS` lists the links under `~\.claude\mods`, `;`-separated; `claude plugin validate ~\.claude\mods\<mod>` passes.
5. In a throwaway folder outside the repository, start a new session of each app and confirm the skills (`/`), the mods and the rules appear.

When one of these fails, see [Troubleshooting](../reference/troubleshooting.md).

## Migrating from 1.5

1.6.0 replaces the separate skills, mods and rules mechanisms with this one. The old shapes are deprecated, keep working, and are removed in 2.0.0; `Test-ConfigurationSchema` names each one still in use at every profile load and at the start of every Bootstrap, and `Deploy-AiArtifacts` reports each one it mapped.

| 1.5 | 1.6 | Until 2.0.0 |
| --- | --- | ----------- |
| `AiSkills.Sources.<name>` (`Folders`) | `AiArtifacts.Sources.<name>` with `Skills` | read as a source (an `AiArtifacts.Sources` entry of the same name wins) |
| `AiMods.Sources.<name>` (`Folders`, `Exclude`, `SkipPaths`) | `AiArtifacts.Sources.<name>` with `Mods` | read as a source |
| `AiSkills.Root`, `AiMods.Root` | `AiArtifacts.Root` (the folder holding `Skills` and `Mods`) | a non-default value moves `Root` to its parent folder |
| `AiSkills.Harnesses`, `AiMods.Harnesses` | `AiHarnesses` entries and `AiArtifacts.Deploy` | not read; warned about |
| `PathTemplates.SymbolicLinks.AI` (the CoreAiRules links) | the rules item `AI\Rules\own\<Name>\` with `AiArtifacts.Use.Rules` and `Deploy` | still linked by `SymbolicLinkMaker`; the item it targets becomes `Use.Rules` when none is set |
| `BootstrapConfig.Steps.CoreAiRules`, `.AiSkills`, `.AiMods` | `BootstrapConfig.Steps.AiArtifacts` | aliases: any of them on (with no `AiArtifacts` entry) turns the step on, and with `Deploy` empty the machine deploys into `claude-code`, `codex` and `gemini-cli`, the folders the old commands wrote |
| `Deploy-AiSkills`, `Deploy-AiMods`, `Deploy-CoreAiRules` | `Deploy-AiArtifacts -Kind Skills`, `Mods`, `Rules` | wrappers that warn once per session |
| `Update-AiSkills`, `Update-AiMods` | `Update-AiArtifacts` | wrappers |
| `List-Skills` | `List-AiArtifacts -Kind Skills` (`-Skill` is `-Name`) | wrapper |
| `AI\CoreAiRules.md`, `AI\Claude\managed-settings.json` | `AI\Rules\own\CoreAiRules\RULES.md` and `managed-settings.json` | removed from the base; copy yours before merging |

A migrated `Configuration.local.psd1`, with the rules in `AI\Rules\own\CoreAiRules\` and the old `AiSkills`, `PathTemplates.SymbolicLinks.AI` and step entries removed:

```powershell
@{
    AiArtifacts     = @{
        Sources = @{
            mattpocock = @{
                Repository = "OWNER/skills"
                Ref        = "main"
                Skills     = @("skills/engineering", "skills/productivity")
            }
        }
        Exclude = @("rules/example/CoreAiRules")
        Deploy  = @{
            Default = @("claude-code", "codex", "gemini-cli")
        }
    }
    BootstrapConfig = @{
        Steps = @{
            AiArtifacts = $true
        }
    }
}
```

The prompts and agent the base used to carry (`.github/prompts/add-*`, `oneoff`, `research`, `document`, `.github/agents/researcher.agent.md`) and `AI/Templates`, `AI/Models`, `AI/Providers` are removed in 1.6.0; `document` is the `winux` skill of the same name. Copy what you use into your fork (as `own` skills, prompts or agents) before merging. The `add-*` prompts are covered by the [winux-configurator](../configuration/winux-configurator.md) skill.

## Related

- [AI module reference](../modules/ai.md) - every command
- [AI configuration guides](../configuration/guides/ai/README.md) - the keys, decision by decision
- [AI Skills](skills.md), [AI Mods](mods.md), [CoreAiRules](coreairules.md) - the kind specifics

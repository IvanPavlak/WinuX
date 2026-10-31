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
2. Checkout sources (`AiArtifacts.Checkouts`, in name order) - a local repository whose items are linked straight from its working tree (see [Checkout sources](#checkout-sources)).
3. `winux` - the product skills WinuX ships: [winux-configurator](../configuration/winux-configurator.md) and `document`, which turns a function's comment-based help into its module page entry and configuration guide.
4. `example` - the example rules.
5. Vendored sources (`AiArtifacts.Sources`, in name order), filled by [Update-AiArtifacts](../modules/ai.md#update-aiartifacts).
6. Manifest sources (`AiArtifacts.Manifests`, in name order) - pinned third-party items cloned into a cache outside the repository (see [Manifest sources](#manifest-sources)).

Any other source folder is not read. Leave an item out with an `AiArtifacts.Exclude` entry: `"skills/tdd"` drops it from every source, `"skills/winux/document"` from one, `"skills/my-source/*"` every item of one source (wildcards work), and `@{ Item = "skills/tdd"; Machine = "Work" }` on one machine type. An [AI profile](profiles.md) adds its own `Exclude` entries, and its `Include` entries limit a kind they name to the matching items. The `source` of an item is its folder name (`own`, `winux`, `example`, a vendored source), the checkout source's name for a checkout item, and the lowercased upstream owner for a manifest item (the `<owner>` of its `https://github.com/<owner>/<repo>`, not the manifest source's name): `"skills/my-checkout/*"` matches only that checkout's items, `"skills/some-owner/tdd"` only the manifest row from that owner's repository.

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
| `Hooks` | `claude-plugin-dirs`: sets `env.CLAUDE_CODE_PLUGIN_DIRS` of `~\.claude\settings.json` to the links, **joined with `;`** (`:` in WSL), then every entry added by hand, and runs `claude plugin validate` on each (a missing or rejecting CLI only warns); `managed-settings`: the destination is an administrator-owned rendered copy, never a link, and the WSL twin is written as root (see [CoreAiRules - Managed settings copy](coreairules.md#managed-settings-copy)) |
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
- MCP servers are not an artifact kind: each app keeps them inside its own configuration file, so [Deploy-AiMcpServers](../modules/ai.md#deploy-aimcpservers) writes them there instead of linking anything. See [AI MCP Servers](mcp-servers.md).

Sources: Claude Code [skills](https://code.claude.com/docs/en/skills), [.claude directory](https://code.claude.com/docs/en/claude-directory), [managed settings](https://code.claude.com/docs/en/managed-settings) and [environment variables](https://code.claude.com/docs/en/env-vars); Codex [skills](https://learn.chatgpt.com/docs/build-skills), [custom prompts](https://learn.chatgpt.com/docs/custom-prompts), [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) and [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents); Gemini CLI [skills](https://geminicli.com/docs/cli/skills/), [custom commands](https://geminicli.com/docs/cli/custom-commands/), [subagents](https://geminicli.com/docs/core/subagents/) and [GEMINI.md](https://geminicli.com/docs/cli/gemini-md/); Copilot CLI [skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills), [custom agents](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli) and [custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions), VS Code [agent skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills); [T3 Code](https://github.com/pingdotgg/t3code).

### WSL twins

A harness with `WSL = $true` deploys every destination that has a WSL twin inside the default distribution too (`DefaultWSLDistribution`, as `DefaultWSLUsername`): a `{User}` path maps onto `/home/<DefaultWSLUsername>/`, any other path needs its own `WSLPath`. The links point at the `/mnt/<drive>` mount of the repository. Each destination is one `wsl -e sh <script>` call, run as the WSL user, or as root for a `managed-settings` destination (`/etc/claude-code` is root-owned). The `claude-plugin-dirs` hook updates the WSL user's `settings.json` from Windows through the `\\wsl.localhost\<distro>` share. Without a distribution or a username, nothing is deployed in WSL.

## Selection

Every item of every source read goes to every active app that accepts its kind, minus the `Exclude` entries. A `File` destination takes the one item `AiArtifacts.Use` names for its kind; without a `Use` entry it links nothing. With an [AI profile](profiles.md) active, the profile's `Rules` is the rules entry and its `Deploy` the harness list. A `Use` value may be per machine type:

```powershell
AiArtifacts = @{
    Use     = @{ Rules = @{ Default = "CoreAiRules"; Work = "WorkRules" } }
    Exclude = @("rules/example/CoreAiRules", @{ Item = "skills/tdd"; Machine = "Work" })
}
```

## Deploying

[Deploy-AiArtifacts](../modules/ai.md#deploy-aiartifacts) deploys, `-Kind` limits it to some kinds and `-WhatIf` reports what a run would change (`MISSING`, `WRONG`, `DIFFERS`, `STALE`) and changes nothing. It is the Bootstrap step `AiArtifacts`, off by default; `AiMarketplaces` (below) and `AiMcpServers` ([AI MCP Servers](mcp-servers.md)) are their own steps.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiArtifacts    = $true
        AiMarketplaces = $true
    }
}
```

Behaviour kept for every kind: a folder destination that is itself a link into the repository is replaced by a real folder, one that links elsewhere (or a file in its place) is skipped; a real file or folder where a link or copy goes is first copied into `Backups\Windows\SymbolicLinks\AiArtifacts.<kind>.<item>\<timestamp>\` (see [Backups](../reference/backups.md)), and when that copy fails the item is skipped; only dangling links that point into the artifacts root, the manifest cache or a checkout source are pruned, a link to anything else is never touched. The run needs administrator rights (symbolic links and `C:\Program Files`), like `SymbolicLinkMaker`.

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

## Checkout sources

A checkout source is a local repository you develop artifacts in. Its items are linked straight from its working tree - never copied, no `UPSTREAM.md` - so a `git pull` of that repository updates every machine's linked items at once:

```powershell
AiArtifacts = @{
    Checkouts = @{
        "my-skills" = @{
            Path   = "{Dev}\MySkills"     # {Dev}, {User}, {RepoRoot} expand
            Skills = @("skills")          # per kind, its folders holding items (no kind key: Skills = @("skills"))
        }
    }
}
```

A checkout source is read right after `own`, so it wins a name clash with everything else. A missing folder only yields fewer items.

## Manifest sources

A manifest source is a manifest file, typically kept in a checkout source, that pins third-party items to a commit:

```powershell
AiArtifacts = @{
    Manifests = @{ "my-skills" = @{ Path = "{Dev}\MySkills\third-party\manifest.tsv" } }
}
```

The format (shared with Foundation, read by [Get-AiArtifactManifest](../modules/ai.md#get-aiartifactmanifest)):

- UTF-8, tab-separated, one header row, `#` starts a comment line, blank lines are ignored.
- Columns, in order:

| Column | Meaning |
| ------ | ------- |
| `name` | the item's folder name in its source; also its installed name unless `install` gives `rename=` |
| `kind` | `skills`, `mods`, `rules`, `prompts` or `agents` |
| `scope` | `*` (every profile), one or more [AI profile](profiles.md) names separated by commas, or `repo:<name>` for an item linked into one repository only |
| `source` | `https://github.com/<owner>/<repo>` |
| `ref` | a full 40-character commit SHA, never a branch |
| `path` | the item's folder inside the source |
| `install` | `clone`, optionally followed by `rename=<new-name>` and/or `strip-invocation-guard` |

```text
name	kind	scope	source	ref	path	install
tdd	skills	*	https://github.com/MyOrg/skills	0123456789abcdef0123456789abcdef01234567	skills/tdd	clone
grill	skills	Personal	https://github.com/MyOrg/skills	0123456789abcdef0123456789abcdef01234567	skills/grill	clone rename=grill-me strip-invocation-guard
design	skills	repo:MyProject	https://github.com/MyOrg/skills	0123456789abcdef0123456789abcdef01234567	skills/design	clone
```

How the rows are deployed:

- Each `source` + `ref` a row that applies here needs is cloned once into the manifest cache, outside every repository: `%LOCALAPPDATA%\WinuX\ai-manifests\<owner>\<repo>\<ref>\` ([Sync-AiManifestCache](../modules/ai.md#sync-aimanifestcache), run by `Deploy-AiArtifacts` before it plans and by `Update-AiArtifacts`). Only the pinned commit is fetched (a shallow fetch by id, no history; the full clone only when the server refuses that), each fetch is announced as it starts, and git's credential prompts are off, so a private or renamed upstream fails at once instead of waiting. A ref is immutable, so a clone that is there is never fetched again; a clone is made in `<ref>.partial` and renamed only when its checkout succeeded.
- A row applies when its scope is `*` or names the active AI profile; with profiles off, only `*` and `repo:` rows apply.
- A manifest item's source label is its upstream owner, lowercased: it is listed as `<owner> (manifest)` and matched by `Exclude` and `Include` entries as `kind/<owner>/name`. instead of the clone's folder: `<ref>.derived\<link-name>\` in the cache (the `rename=` name, else the row's name), made once. `rename=` rewrites the frontmatter `name:` of its `SKILL.md` to the new name, since Claude Code names a skill by its frontmatter, not its folder; `strip-invocation-guard` removes its `disable-model-invocation` line, so agents can call the skill.
- A `repo:<name>` row (skills only) is linked into that repository's `.claude\skills\`, the repository found by name in `RepositoryGroups`, when `claude-code` is deployed; its link names are added to that repository's `.git\info\exclude`, so nothing is committed.
- A row that breaks the format is reported with its line number and skipped; the others deploy.

`Update-AiArtifacts` clones the refs that are missing, and `Update-AiArtifacts -Check` reports every row whose upstream default branch has moved past its pinned ref (`git ls-remote <source> HEAD`), changing nothing. Moving a row to a newer commit is an edit of the manifest; the next deploy clones the new ref. Upstream licences of adapted items belong in the manifest repository's `licenses/`.

## Marketplaces

Marketplaces are not an artifact kind: their plugins install through Claude Code's own CLI. [Deploy-AiMarketplaces](../modules/ai.md#deploy-aimarketplaces) reads `AiMarketplaces` and is the Bootstrap step `AiMarketplaces`; see [AI Mods - Marketplaces](mods.md#marketplaces). A plugin installed from a marketplace must not also be a mod in `AI\Mods`: Claude Code would load it twice.

## Verification (per machine, after enabling)

1. `Deploy-AiArtifacts -WhatIf` ends with a success line or names what is missing.
2. `List-AiArtifacts -ListDiscrepancies` reports nothing: every item is deployed into every destination of the harnesses turned on.
3. The rules: `(Get-Item ~\.claude\CLAUDE.md).LinkTarget` prints a path inside `AI\Rules\`, and `(Get-Item "C:\Program Files\ClaudeCode\managed-settings.json").LinkTarget` prints nothing (a copy, not a link); in WSL, `readlink ~/.claude/CLAUDE.md` prints a `/mnt/<drive>/...` path and `ls -l /etc/claude-code/` shows root-owned files. With an AI profile, `Test-AiProfile` exits 0.
4. The sources: `List-AiArtifacts` shows each group with its source kind (`checkout`, `product`, `vendored`, `manifest`, `manifest, repo:<name>`); a manifest item's group is named by its upstream owner.
5. The mods: `(Get-Content ~\.claude\settings.json | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS` lists the links under `~\.claude\mods`, `;`-separated; `claude plugin validate ~\.claude\mods\<mod>` passes.
6. In a throwaway folder outside the repository, start a new session of each app and confirm the skills (`/`), the mods and the rules appear.

When one of these fails, see [Troubleshooting](../reference/troubleshooting.md).

## Related

- [AI module reference](../modules/ai.md) - every command
- [AI configuration guides](../configuration/guides/ai/README.md) - the keys, decision by decision
- [AI Skills](skills.md), [AI Mods](mods.md), [CoreAiRules](coreairules.md) - the kind specifics

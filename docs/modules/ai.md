# AI Module

The AI module handles **machine-global AI coding agent setup**: the CoreAiRules enforcement layer, Agent Skills deployment across Claude Code, Codex CLI and Gemini CLI, and Claude Code mods vendoring and deployment. All three are opt-in (`BootstrapConfig.Steps.CoreAiRules`, `BootstrapConfig.Steps.AiSkills`, `BootstrapConfig.Steps.AiMods`) - a vanilla bootstrap imposes no AI policy, links no skills and deploys no mods. Design pages: [CoreAiRules](../ai/coreairules.md), [AI Skills](../ai/skills.md) and [AI Mods](../ai/mods.md).

## [Deploy-AiMarketplaces](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Deploy-AiMarketplaces.ps1)

- **Description:** Registers every Claude Code plugin marketplace under `AiMarketplaces.Marketplaces` in the user's `~\.claude\settings.json` (`extraKnownMarketplaces.<name>`, the GitHub repository as the source, every other setting kept, written through [Set-ClaudeSettingsKey](#set-claudesettingskey)), writes the plugins' options from `AiMarketplaces.PluginConfigs` beneath `pluginConfigs.<plugin>` one child key at a time, and installs every listed plugin as `<plugin>@<marketplace>` through `claude plugin install` unless `claude plugin list --json` already shows it. A missing CLI only warns - the settings are deployed regardless. Inside WSL (`DefaultWSLDistribution` and `DefaultWSLUsername` set, share reachable) the marketplaces and options are written to the WSL user's settings file too; the install there is left to the user. Idempotent. Called by Bootstrap when the opt-in `BootstrapConfig.Steps.AiMarketplaces` toggle is enabled (OFF by default).
- **Parameters:** -Command
- **Usage:** `Deploy-AiMarketplaces`

A plugin loaded from a folder by [Deploy-AiMods](#deploy-aimods) and installed from a marketplace would run twice: give each plugin one loading path. Design: [AI Mods - Marketplaces](../ai/mods.md#marketplaces).

## [Deploy-AiMods](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Deploy-AiMods.ps1)

- **Description:** Links every Claude Code mod under the mods root (`AiMods.Root`, default `AI/Mods`, one subfolder per source; a mod is a folder holding `.claude-plugin\plugin.json`) into each directory of `AiMods.Harnesses` (default `~\.claude\mods`), one symbolic link per mod, then points Claude Code at them by setting the single key `env.CLAUDE_CODE_PLUGIN_DIRS` of `~\.claude\settings.json` - the links of the first harness, then every entry added by hand, with entries under that harness that no longer have a mod dropped (merge by [Resolve-AiModsPluginDirs](#resolve-aimodsplugindirs), write by [Set-ClaudeSettingsEnv](#set-claudesettingsenv), every other setting kept). Does the same inside WSL (`/home/<DefaultWSLUsername>/.claude/mods`, links to the `/mnt/<drive>` mount, the WSL settings file edited through `\\wsl.localhost\<distro>` with `:` as the separator). Finally runs [Test-AiModsCli](#test-aimodscli) and only warns when the `claude` CLI is missing or rejects a mod - links and settings are always deployed. Reads the roster through [Get-AiModRoster](#get-aimodroster) (first source by name wins a name clash) and links through [New-WindowsSymbolicLink](system.md#new-windowssymboliclink). Requires administrator privileges. Called by Bootstrap when the opt-in `BootstrapConfig.Steps.AiMods` toggle is enabled (OFF by default).
- **Usage:** `Deploy-AiMods`

Claude Code loads mods (function-hook plugins) from the folders named in `CLAUDE_CODE_PLUGIN_DIRS`, which it reads from the process environment or the `env` block of the user settings file - never from a project's settings - so one link per mod plus that one key reaches every session on the machine. The harness rules match [Deploy-AiSkills](#deploy-aiskills): a whole-directory link into the repository at the harness path is replaced by a real directory, dangling links into the mods root are pruned, links to anything else are never touched. The WSL settings update is skipped with a warning when the share is unreachable. Idempotent - re-runs self-heal.

**See also:** [Update-AiMods](#update-aimods), [Resolve-AiModsConfig](#resolve-aimodsconfig), [AI Mods](../ai/mods.md)

## [Deploy-AiSkills](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Deploy-AiSkills.ps1)

- **Description:** Links every skill under the skills root (`AiSkills.Root`, default `AI/Skills`, one subfolder per source) into each AI harness's user-level skills directory (`AiSkills.Harnesses`, default `~\.claude\skills` for Claude Code and `~\.agents\skills` for Codex CLI and Gemini CLI), one symbolic link per skill, on Windows and inside WSL (`/home/<DefaultWSLUsername>/...`). Replaces a whole-directory link into the repository at a harness path with a real directory, prunes dangling links into the skills root, and never touches links to anything else. Called by Bootstrap when the opt-in `BootstrapConfig.Steps.AiSkills` toggle is enabled (OFF by default).
- **Usage:** `Deploy-AiSkills`

Every harness discovers user-level skills from one flat directory of `<skill>/SKILL.md`, and none recurses, so the repository's per-source layout (`AI/Skills/<source>/<skill>/`) is flattened by linking each skill individually rather than linking the whole root. The harness directories therefore stay machine-local: a skill installed there by another tool coexists, and the whole-directory linking style some setups start with is migrated automatically. The same skill name under two sources is reported and the first source (by name) wins.

Windows links go through [New-WindowsSymbolicLink](system.md#new-windowssymboliclink) (backs up a real folder of the same name, self-heals an existing link), and the function checks for administrator privileges up front (`Test-AdminPrivileges`, like `SymbolicLinkMaker`). WSL links are created by one script per harness directory, run with `wsl -e sh` as the WSL user (bypassing the login shell, which would otherwise split an inline script), pointing at the `/mnt/<drive>` mount of the repository; skipped when no distribution or `DefaultWSLUsername` is configured. Idempotent - re-runs self-heal.

**See also:** [Update-AiSkills](#update-aiskills), [Resolve-AiSkillsConfig](#resolve-aiskillsconfig), [SymbolicLinkMaker](system.md#symboliclinkmaker)

## [Deploy-CoreAiRules](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Deploy-CoreAiRules.ps1)

- **Description:** Deploys the CoreAiRules enforcement layer into WSL by symlinking `AI/Claude/managed-settings.json` to `/etc/claude-code/managed-settings.json` inside the default WSL distribution, so Claude Code sessions running in WSL are governed by the same managed (admin-owned, highest-precedence) settings as Windows sessions. Does nothing when the configured distribution is not installed, and never links to a missing target. Called by Bootstrap when the opt-in `BootstrapConfig.Steps.CoreAiRules` toggle is enabled (OFF by default - machine-global AI policy is never imposed by a vanilla bootstrap).
- **Usage:** `Deploy-CoreAiRules`

This is the one CoreAiRules link `SymbolicLinkMaker` cannot create: `/etc` is root-owned and the engine's WSL branch never elevates, while this function runs every `wsl.exe` call as root (`wsl -u root`, no sudo prompt). Every other CoreAiRules link (the per-harness instruction files on Windows and in WSL, and the Windows managed settings under `C:\ProgramData\ClaudeCode`) is a regular `PathTemplates.SymbolicLinks` entry handled by `SymbolicLinkMaker` - the commented `AI` block in `Configuration.psd1` is the opt-in template.

Idempotent (`ln -sfn`): reruns self-heal the link, so it is safe to run any time. The full CoreAiRules design (layers, deployed paths, verification) is documented in [CoreAiRules](../ai/coreairules.md).

**See also:** [SymbolicLinkMaker](system.md#symboliclinkmaker), [Configure-WSL](system.md#configure-wsl)

## [Get-AiModRoster](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiModRoster.ps1)

- **Description:** Enumerates every Claude Code mod under the mods root (`<Root>\<source>\<mod>\.claude-plugin\plugin.json`) and returns it flattened by mod name as `@{ Root; Mods; Duplicates }`: `Mods` is an ordered map of name to `@{ Name; Path; Source }` (sources walked in name order, the first source wins a name clash), `Duplicates` lists the losing entries with the source they lost to. A folder without the manifest is not a mod; a missing root yields an empty roster. The single reading [Deploy-AiMods](#deploy-aimods) links from.
- **Parameters:** -Root
- **Usage:** `Get-AiModRoster`, `(Get-AiModRoster).Mods.Keys`, `Get-AiModRoster -Root "C:\Repo\AI\Mods"`

**See also:** [Get-AiSkillRoster](#get-aiskillroster)

## [Get-AiSkillDescription](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiSkillDescription.ps1)

- **Description:** Extracts the `description:` from a `SKILL.md` YAML frontmatter as one line of Markdown table text: single-line, quoted (inner escaped quotes unescaped) and folded or literal block values are all flattened, and pipes are escaped. Returns an empty string when the file has no frontmatter or no description. Used by `Update-AiSkills` for the skill table in `UPSTREAM.md`.
- **Parameters:** -SkillFile
- **Usage:** `Get-AiSkillDescription -SkillFile "C:\Repo\AI\Skills\mattpocock\grill-me\SKILL.md"`

## [Get-AiSkillManifest](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiSkillManifest.ps1)

- **Description:** Reads the `UPSTREAM.md` manifest that `Update-AiSkills` writes into a vendored source folder and returns a hashtable with `Commit` (the pinned upstream sha) and `Skills` (every vendored skill name). A missing manifest yields an empty commit and no skills. `Update-AiSkills` uses the names to know which folders it owns and the commit for `-Check`; [Update-AiMods](#update-aimods) writes the same format and reads it back the same way, the `Skills` list then holding mod names.
- **Parameters:** -Path
- **Usage:** `(Get-AiSkillManifest -Path "C:\Repo\AI\Skills\mattpocock\UPSTREAM.md").Skills`

## [Get-AiSkillRoster](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiSkillRoster.ps1)

- **Description:** Walks `<Root>\<source>\<skill>\SKILL.md` and returns the flattened roster every harness needs: `Root`, `Skills` (an ordered map of skill name to `Name`, `Path` and `Source`, in source-then-name order) and `Duplicates` (one entry per losing name, with the source that won). A folder without a `SKILL.md` is not a skill, and when two sources carry the same name the first source alphabetically wins. A missing root yields an empty roster rather than an error. Shared by `Deploy-AiSkills` and `List-Skills` so what is listed is exactly what is deployed; it writes nothing to the log, leaving each caller to report duplicates in its own voice.
- **Parameters:** -Root
- **Usage:** `(Get-AiSkillRoster).Skills.Count`, `(Get-AiSkillRoster -Root "C:\Repo\AI\Skills").Skills['teach-me'].Source`

## [List-Skills](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/List-Skills.ps1)

- **Description:** The catalog counterpart to `Deploy-AiSkills`: lists the Agent Skills the repository carries, grouped by source, each with the `description:` from its own `SKILL.md` frontmatter. The roster comes from disk (`Get-AiSkillRoster`), not from documentation, because skills are mostly vendored and only disk stays honest across a refresh. `-Source` and `-Skill` filter, resolved by number or name like `List-Functions -Category` (pass an empty value, `-Source @()`, to pick from the menu). `-ListDiscrepancies` compares what the repository carries against what is actually linked into the Windows harness directories - declared against in effect, the analogue of `List-Functions -ListDiscrepancies` - reporting a skill that is not linked, a harness entry that shadows a skill with a real folder or points elsewhere, and a link into the skills root whose skill is gone; links to anything else are ignored. WSL harnesses are not read (that means shelling into the distribution); re-run `Deploy-AiSkills` to reconcile those. `-Quiet` suppresses the all-clear banner. The catalog is drawn with the same helpers `List-Functions` uses - a [Create-CenteredBorder](helper.md#create-centeredborder) group header per source and [Show-FunctionDetails](helper.md#show-functiondetails) per entry, so a skill reads exactly like a function entry (name, indented description, then indented `Key => value` rows) in the `ShowFunctionDetailsColors` palette. Everything it emits on its own account goes through the Logging module, so the borders, the audit findings and the all-clear are mirrored into the session log.
- **Parameters:** -Source, -Skill, -ListDiscrepancies, -Quiet
- **Usage:** `List-Skills`, `List-Skills -Source own`, `List-Skills -ListDiscrepancies`

## [Resolve-AiModsConfig](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Resolve-AiModsConfig.ps1)

- **Description:** Resolves the `AiMods` configuration section into one hashtable every AI mods function shares: `Root` (default `{RepoRoot}\AI\Mods`) and `Harnesses` (default `{User}\.claude\mods`) with `{RepoRoot}`, `{User}` and `{AppData}` expanded, `WSLHarnesses` derived from the `{User}` entries and `DefaultWSLUsername`, `Sources` untouched, and the derived (not configurable) Claude Code settings files `SettingsPath` (`~\.claude\settings.json`) and `WSLSettingsPath` (`/home/<DefaultWSLUsername>/.claude/settings.json`, empty without a WSL username). Every key falls back to its default, so the empty base configuration resolves to a usable, empty setup.
- **Parameters:** -Configuration, -RepoRoot
- **Usage:** `Resolve-AiModsConfig`, `(Resolve-AiModsConfig).Root`

**See also:** [Resolve-AiSkillsConfig](#resolve-aiskillsconfig)

## [Resolve-AiModsPluginDirs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Resolve-AiModsPluginDirs.ps1)

- **Description:** Computes the new `CLAUDE_CODE_PLUGIN_DIRS` value without reading or writing anything: every deployed link first, in the order given, then every existing entry NOT under the harness directory verbatim and in its original order (plugins added by hand, `~`-prefixed ones included); existing entries under the harness that were not deployed are stale and dropped, empty entries are dropped and duplicates collapse to their first occurrence. With `;` (Windows) paths compare case-insensitively, with any other separator exactly. Used by [Deploy-AiMods](#deploy-aimods) for both the Windows and the WSL settings file.
- **Parameters:** -Existing, -Deployed, -Harness, -Separator
- **Usage:** `Resolve-AiModsPluginDirs -Existing $current -Deployed $links -Harness "$env:USERPROFILE\.claude\mods" -Separator ';'`

## [Resolve-AiSkillsConfig](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Resolve-AiSkillsConfig.ps1)

- **Description:** Resolves the `AiSkills` configuration section into one hashtable the AI skills functions share: `Root` (skills root, default `{RepoRoot}\AI\Skills`), `Harnesses` (Windows skills directories, default `{User}\.claude\skills` and `{User}\.agents\skills`), `WSLHarnesses` (the `{User}` entries mapped onto `/home/<DefaultWSLUsername>/`, empty when no WSL username is configured) and `Sources` (the configured upstreams, untouched). Expands `{RepoRoot}`, `{User}` and `{AppData}` only - the section is machine-type independent. Every key falls back to its default when missing, so the empty base configuration resolves to a usable setup.
- **Parameters:** -Configuration, -RepoRoot
- **Usage:** `(Resolve-AiSkillsConfig).Root`, `(Resolve-AiSkillsConfig).WSLHarnesses`

## [Set-ClaudeSettingsEnv](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Set-ClaudeSettingsEnv.ps1)

- **Description:** Sets one variable in the `env` block of a Claude Code `settings.json` (default `~\.claude\settings.json`; a `\\wsl.localhost` path edits a WSL user's file) by reading the whole document, setting exactly that key and writing the whole document back, so every other top-level key, nested object and `env` variable survives. A missing file is created with only the key; a file without `env` gains one; an unchanged value writes nothing. Unparseable JSON, a non-object top level or a non-object `env` is logged as an error, left untouched, and returns `$false`. Writes UTF-8 without a BOM, two-space indented with LF line endings, and keeps date-like strings verbatim. Supports `-WhatIf`. Used by [Deploy-AiMods](#deploy-aimods).
- **Parameters:** -Name, -Value, -SettingsPath, -WhatIf
- **Usage:** `Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "C:\Users\You\.claude\mods\my-mod"`, `Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "" -WhatIf`

## [Set-ClaudeSettingsKey](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Set-ClaudeSettingsKey.ps1)

- **Description:** Sets one key, at any depth, of a Claude Code `settings.json` (default `~\.claude\settings.json`; a `\\wsl.localhost` path edits a WSL user's file) by its dotted path, e.g. `extraKnownMarketplaces.my-marketplace` or `pluginConfigs.my-plugin.options`: reads the whole document, sets exactly that key, creates the objects along the path, and writes the whole document back, so every other key survives. A hashtable or array value becomes the JSON it describes; a value already equal (as JSON) writes nothing; a missing file is created with only the path. Unparseable JSON, a non-object top level or a non-object value along the path is logged as an error, left untouched, and returns `$false`. Writes UTF-8 without a BOM, two-space indented with LF line endings, and keeps date-like strings verbatim. Supports `-WhatIf`. The generic sibling of [Set-ClaudeSettingsEnv](#set-claudesettingsenv); used by [Deploy-AiMarketplaces](#deploy-aimarketplaces).
- **Parameters:** -Path, -Value, -SettingsPath, -WhatIf
- **Usage:** `Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.my-marketplace" -Value @{ source = @{ source = "github"; repo = "MyOrg/MyMarketplace" } }`, `Set-ClaudeSettingsKey -Path "pluginConfigs.my-plugin.options" -Value @{ theme = "light" } -WhatIf`

## [Test-AiModsCli](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Test-AiModsCli.ps1)

- **Description:** Checks that the Claude Code CLI resolves on PATH and runs `claude plugin validate <path>` on every given mod, returning `@{ Installed; Invalid }` - `Invalid` holds the mod paths whose validation exited non-zero or threw, and is empty when the CLI is missing (nothing could be checked). The CLI's validator is the practical gate for the mod API, since an older CLI rejects a mod it cannot load. [Deploy-AiMods](#deploy-aimods) only warns on the result.
- **Parameters:** -ModPath, -Command
- **Usage:** `Test-AiModsCli -ModPath "$env:USERPROFILE\.claude\mods\my-mod"`, `(Test-AiModsCli -ModPath $links).Invalid`

## [Update-AiMods](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Update-AiMods.ps1)

- **Description:** Vendors Claude Code mods from the upstream repositories in `AiMods.Sources` (`Repository`, `Ref`, `Folders`, `Exclude`, `SkipPaths`) into `<Root>\<source>\<mod>\`, pinned: resolves `Ref` to an exact commit through the GitHub API, downloads that commit's archive, and takes each configured folder (default `.`, the repository root) as one mod when it holds `.claude-plugin\plugin.json`, otherwise each subfolder that does. Each mod is named by its `plugin.json` `name` (else the folder name, or the repository name for a root mod) and copied without the top-level entries in `SkipPaths` (default `.git`, `.github`, `tests`, `design`, `docs`). Writes `UPSTREAM.md` in the exact `Update-AiSkills` format (read back by [Get-AiSkillManifest](#get-aiskillmanifest)) and copies the upstream license. Only mods listed in the previous manifest are replaced, so hand-made folders survive; a network failure leaves the vendored copy untouched. `-Check` compares each pinned commit with the upstream head and changes nothing. Private repositories work when a GitHub token is available: `GITHUB_TOKEN`, else `GH_TOKEN`, else `gh auth token` from a signed-in GitHub CLI; both requests then authenticate and the archive comes from the API's zipball endpoint. The token goes only to `api.github.com` and is never logged. Without one, a private repository answers 404 and the error says how to authenticate. Not a Bootstrap step: the vendored tree is committed, and [Deploy-AiMods](#deploy-aimods) links it.
- **Parameters:** -Source, -Check
- **Usage:** `Update-AiMods`, `Update-AiMods -Source my-mod`, `Update-AiMods -Check`, `$env:GITHUB_TOKEN = "<token>"; Update-AiMods -Source my-private-mod`

**See also:** [Update-AiSkills](#update-aiskills), [AI Mods](../ai/mods.md)

## [Update-AiSkills](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Update-AiSkills.ps1)

- **Description:** Vendors Agent Skills from the configured upstream repositories (`AiSkills.Sources.<name>`: `Repository`, `Ref`, `Folders`, `Exclude`) into `<Root>\<name>\`, flat and pinned: resolves `Ref` to an exact commit through the GitHub API, downloads that commit's archive, copies every skill folder (a directory holding `SKILL.md`) found under `Folders` with the category level dropped, writes `UPSTREAM.md` (repository, commit, fetch time, folders, exclusions, skill table) and the upstream license. Removes only the skills the previous manifest lists, so hand-made folders survive. `-Check` compares each pinned commit with the upstream head and changes nothing. Not a Bootstrap step; no-ops until a fork configures a source.
- **Parameters:** -Source, -Check
- **Usage:** `Update-AiSkills`, `Update-AiSkills -Source mattpocock`, `Update-AiSkills -Check`

Upstreams nest their skills by category (`skills/engineering/grill-me`) while every harness requires `<skill>/SKILL.md` at the top level, which is why the copy is flattened. Supporting files inside a skill (`scripts/`, format documents, `agents/openai.yaml`) are copied as they are. Hand-written skills belong in their own source folder without a manifest - by convention `<Root>\own\` - which no refresh ever touches. A network failure is reported per source and leaves that source's vendored copy untouched; after a successful refresh, review the diff, then run `Deploy-AiSkills` (or `Bootstrap`) to link new skills into the harnesses.

**See also:** [Deploy-AiSkills](#deploy-aiskills), [Get-AiSkillManifest](#get-aiskillmanifest), [Get-AiSkillDescription](#get-aiskilldescription)

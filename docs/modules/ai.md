# AI Module

The AI module handles **machine-global AI coding agent setup**: the CoreAiRules enforcement layer and Agent Skills deployment across Claude Code, Codex CLI and Gemini CLI. Both are opt-in (`BootstrapConfig.Steps.CoreAiRules`, `BootstrapConfig.Steps.AiSkills`) - a vanilla bootstrap imposes no AI policy and links no skills. Design pages: [CoreAiRules](../ai/coreairules.md) and [AI Skills](../ai/skills.md).

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

## [Get-AiSkillDescription](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiSkillDescription.ps1)

- **Description:** Extracts the `description:` from a `SKILL.md` YAML frontmatter as one line of Markdown table text: single-line, quoted (inner escaped quotes unescaped) and folded or literal block values are all flattened, and pipes are escaped. Returns an empty string when the file has no frontmatter or no description. Used by `Update-AiSkills` for the skill table in `UPSTREAM.md`.
- **Parameters:** -SkillFile
- **Usage:** `Get-AiSkillDescription -SkillFile "C:\Repo\AI\Skills\mattpocock\grill-me\SKILL.md"`

## [Get-AiSkillManifest](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Get-AiSkillManifest.ps1)

- **Description:** Reads the `UPSTREAM.md` manifest that `Update-AiSkills` writes into a vendored source folder and returns a hashtable with `Commit` (the pinned upstream sha) and `Skills` (every vendored skill name). A missing manifest yields an empty commit and no skills. `Update-AiSkills` uses the names to know which folders it owns and the commit for `-Check`.
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

## [Resolve-AiSkillsConfig](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Resolve-AiSkillsConfig.ps1)

- **Description:** Resolves the `AiSkills` configuration section into one hashtable the AI skills functions share: `Root` (skills root, default `{RepoRoot}\AI\Skills`), `Harnesses` (Windows skills directories, default `{User}\.claude\skills` and `{User}\.agents\skills`), `WSLHarnesses` (the `{User}` entries mapped onto `/home/<DefaultWSLUsername>/`, empty when no WSL username is configured) and `Sources` (the configured upstreams, untouched). Expands `{RepoRoot}`, `{User}` and `{AppData}` only - the section is machine-type independent. Every key falls back to its default when missing, so the empty base configuration resolves to a usable setup.
- **Parameters:** -Configuration, -RepoRoot
- **Usage:** `(Resolve-AiSkillsConfig).Root`, `(Resolve-AiSkillsConfig).WSLHarnesses`

## [Update-AiSkills](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/AI/Functions/Update-AiSkills.ps1)

- **Description:** Vendors Agent Skills from the configured upstream repositories (`AiSkills.Sources.<name>`: `Repository`, `Ref`, `Folders`, `Exclude`) into `<Root>\<name>\`, flat and pinned: resolves `Ref` to an exact commit through the GitHub API, downloads that commit's archive, copies every skill folder (a directory holding `SKILL.md`) found under `Folders` with the category level dropped, writes `UPSTREAM.md` (repository, commit, fetch time, folders, exclusions, skill table) and the upstream license. Removes only the skills the previous manifest lists, so hand-made folders survive. `-Check` compares each pinned commit with the upstream head and changes nothing. Not a Bootstrap step; no-ops until a fork configures a source.
- **Parameters:** -Source, -Check
- **Usage:** `Update-AiSkills`, `Update-AiSkills -Source mattpocock`, `Update-AiSkills -Check`

Upstreams nest their skills by category (`skills/engineering/grill-me`) while every harness requires `<skill>/SKILL.md` at the top level, which is why the copy is flattened. Supporting files inside a skill (`scripts/`, format documents, `agents/openai.yaml`) are copied as they are. Hand-written skills belong in their own source folder without a manifest - by convention `<Root>\own\` - which no refresh ever touches. A network failure is reported per source and leaves that source's vendored copy untouched; after a successful refresh, review the diff, then run `Deploy-AiSkills` (or `Bootstrap`) to link new skills into the harnesses.

**See also:** [Deploy-AiSkills](#deploy-aiskills), [Get-AiSkillManifest](#get-aiskillmanifest), [Get-AiSkillDescription](#get-aiskilldescription)

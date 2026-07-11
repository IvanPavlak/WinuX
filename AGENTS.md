# Project Guidelines

## Repository Overview

This is a centralized dotfiles repository that automates all system configurations across multiple machines and operating systems. It uses a PowerShell module architecture with a single `Configuration.psd1` as the central hub for Windows. Linux integrations is yet to be made.

**Before working on any task**, read the relevant context document:

- General repository work → `AI/Context/REPOSITORY_CONTEXT.md`
- Windows/PowerShell work → `AI/Context/WINDOWS_CONTEXT.md`

## Code Style

- **PowerShell conventions**: Read `AI/Instructions/PowerShellConventions.md` before writing or modifying PowerShell code
- **Output formatting**: Read `AI/Instructions/OutputFormatting.md` for function signatures, config entries, and documentation format
- **Configuration changes**: Read `AI/Instructions/ConfigurationPatterns.md` before modifying `Configuration.psd1`
- **Documentation updates**: Read `AI/Instructions/DocumentationStyle.md` before updating user-facing docs
- **Never use em-dashes**: always use a plain hyphen `-` instead of the em-dash character (U+2014), in all prose, comments, documentation, log messages, string literals, and commit messages. The em-dash must not appear in any managed file. See `AI/Instructions/OutputFormatting.md`. (The sole exception is the browser-title regex classes in `Configuration.psd1` `BrowserGroups` and `Window/Layouts/*`.)

## Documentation Updates (Required)

**Docs are always kept up to date.** ANY change - not only to functions - that adds, removes, or alters observable behavior, structure, configuration, data, workflow, or usage MUST update the corresponding documentation in the SAME change. Docs are never a follow-up task: a change that touches a documented surface without updating its page is incomplete. When in doubt about whether a change is user-facing, assume it is and update the docs. The exported-function case below is the most common instance of this rule, not the whole of it - see the trigger lists for the non-function surfaces (configuration, data files, bootstrap flow, AI system, pages) that are equally covered.

Since the 2026-06 documentation refactor, the docsify docs under `docs/` are the **SINGLE SOURCE OF TRUTH**. `README.md` at the repo root is now a **minimal pointer** (logo + intro + demo-video placeholder + link to the docs) and carries NO function reference. NEVER add `#### [Name]` function entries, a function Table of Contents, or per-function content to README, and do NOT update README when a function changes.

Every change that adds, renames, removes, or modifies the **behavior, parameters, or signature** of an exported PowerShell function MUST be reflected in the docs in the same change:

- `docs/modules/<Module>.md` - the function reference. ONE man-style entry per function = a `## [FunctionName](<github-source-url>)` heading followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block (Description first, then Parameters / Usage / Alias as applicable; omit a bullet when not applicable). Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line. Entries are alphabetical within the page.
- The module `.psd1` `FunctionsToExport` - keep it in sync when adding/renaming/removing a function.
- `docs/docs_overview.md` - internal maintenance reference (process + per-module index); update it when adding/renaming/removing a function.
- `docs/_sidebar.md` - only when adding/removing a page (not for per-function changes).

`List-Functions` (Helper module) PARSES the module pages. After adding/renaming/removing a function, update its entry alphabetically in `modules/<Module>.md`, update the module `.psd1` `FunctionsToExport`, and run `List-Functions -ListDiscrepancies` (must report none).

**Fork-only functions (the Custom area):** functions not (yet) shipped by WinuX live under `Windows/PowerShell/Modules/Custom/<Module>/Functions/` and are documented with the SAME man-style entry format in `docs/custom/<module>.md` (the heading link points at the fork's source URL). Their name goes in `Custom.psd1`'s `FunctionsToExport` (the fork-owned manifest, not an engine module's) - which is what makes them autoload - and `List-Functions -ListDiscrepancies` checks them against their `docs/custom/` pages. Graduation into WinuX follows `Windows/PowerShell/Modules/Custom/README.md`.

Use **genericized example values** in docs (placeholders like MyProject, MyRepo, GroupName, Work-PC) - no real personal/work identifiers.

Triggers that require a docs update:

Functions (module reference):

- New exported function (add a `## [Name](url)` man-style entry alphabetically in the matching `docs/modules/<Module>.md`, add it to `FunctionsToExport`, and update `docs_overview.md`)
- Renamed function (rename the entry and its `FunctionsToExport` line; update `docs_overview.md`)
- Removed function (remove the entry and its `FunctionsToExport` line; update `docs_overview.md`)
- New/changed fork-only function (same entry format, but in `docs/custom/<module>.md`; its name goes in `Custom.psd1` `FunctionsToExport`, not an engine module's)
- Parameter added/removed/renamed (update the `**Parameters:**` bullet in the module page entry)
- Behavioral change visible to a caller (update the `**Description:**` bullet in the module page entry)
- New cross-function interaction (e.g. function A now invokes function B for recovery) - note it in the relevant module page entry

Everything else (equally required):

- Configuration schema change - new/renamed/removed `Configuration.psd1` key, changed placeholder, or new machine type - update `docs/configuration/configuration-reference.md` (and `docs/configuration/placeholder-system.md` / `docs/configuration/machine-types.md` as applicable)
- Package or data-file change - `WinGetApps.csv`, Scoop, or Chocolatey app lists, or any `Data/` CSV - update `docs/reference/software-list.md`
- Bootstrap / install / provisioning-flow change - new step, reordering, new package manager, or changed first-run behavior - update the relevant `docs/getting-started/*.md` page (and `docs/modules/bootstrap.md`)
- AI system change - new/renamed/removed prompt, agent, instruction, provider, or template under `AI/` or `.github/` - update `docs/ai/agent-system.md` / `docs/ai/overview.md`
- New user-facing gotcha, failure mode, or workaround - add it to `docs/reference/troubleshooting.md`
- New or removed doc page or module - update `docs/_sidebar.md` and `docs/docs_overview.md`
- Governance/convention change - if you change a rule in `AGENTS.md` or an `AI/Instructions/*` file, mirror it in the other governance surfaces that state the same rule (`AGENTS.md`, `AI/Instructions/`, `.github/instructions/`) so they never disagree

Triggers that do NOT require a docs update:

- Internal refactors with no behavior, signature, config, or data change
- Comment-only / formatting-only changes
- New tests
- Memory file updates

Skipping required documentation updates is treated the same as leaving the change incomplete.

## Architecture

- **Entry point**: `Microsoft.PowerShell_profile.ps1` → Bootstrap module → loads all other modules
- **Config hub**: `Windows/PowerShell/Configuration.psd1` - single source of truth for all settings
- **Modules**: located in `Windows/PowerShell/Modules/` - Application, Bootstrap, Configuration, Git, Helper, System, Window, Workflow, Tests
- **Placeholder system**: `{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}` - expanded at runtime via `Expand-ConfigPaths`
- **Machine types**: PC, Laptop, Work, Test - detected from hostname

## Conventions

- Functions follow `Verb-Noun` naming with comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
- Never write nested functions. Extract helpers into top-level functions in their own `.ps1` file, or into a separate helper script when working in script-only code.
- Each module uses `.psd1` manifest + `.psm1` loader + `Functions/` directory pattern
- Configuration entries use placeholder paths for machine independence
- Browser groups, workspaces, projects, and symbolic links all follow hierarchical hashtable patterns in `Configuration.psd1`
- Tests use Pester framework in `Modules/Tests/`
- Every new exported function should include corresponding tests in `Windows/PowerShell/Modules/Tests/Modules/<Module>/`
- Tests should validate behavior, side effects, branching, and edge cases; do not add tests that only assert output message text

## Running Tests (Delegate to the Developer)

Do NOT run the test suite yourself - no `Import-Module` + `Invoke-Pester`, and no ad-hoc bootstrap/harness scripts. Running tests needs the full profile session loaded and is slow to reconstruct from scratch. Instead, after you add or change functions or tests, give the developer the exact `Run-Tests` command in a single line and ask them to run it and report any failures back to you.

- **Scoped to what you changed (preferred):** `Run-Tests -TestName "<ChangedFunctionOrPattern>"` - matches `*<pattern>*.Tests.ps1`. Run it once per changed area, e.g. `Run-Tests -TestName "Resize-Windows"`. List every command when several areas changed.
- **Whole suite (only for broad/cross-cutting changes):** `Run-Tests`.
- **Diagnosing a failure:** add `-Detailed` for per-test output, e.g. `Run-Tests -TestName "Resize-Windows" -Detailed`.

State which tests each command covers, then wait for the developer's pass/fail report before treating the change as verified. Only run tests yourself if the developer explicitly asks you to.

## AI System

- Centralized AI configuration lives in `AI/` - provider-agnostic, human-readable
- Use `/oneoff` or `/research` prompts for conversation persistence
- Use `/document` to generate documentation from code comments
- Configuration functions in `Modules/Configuration/` for reliable configuration modifications

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

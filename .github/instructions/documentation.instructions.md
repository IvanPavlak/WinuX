---
description: "Use when writing, updating, or generating documentation pages, sidebar navigation, or cross-references in the Docsify documentation site."
applyTo: "docs/**"
---

# Documentation Conventions

Read and follow this instruction file before generating or modifying documentation:

- `AI/Instructions/DocumentationStyle.md` - Docsify structure, sidebar conventions, table formats, cross-references between docs and code

Context for understanding the documented system:

- `AI/Context/REPOSITORY_CONTEXT.md` - Architecture overview and module map
- `AI/Context/WINDOWS_CONTEXT.md` - Full function reference with parameters

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

See `AGENTS.md` for the full critical operations policy.

## Current Docs Model (since the 2026-06 documentation refactor)

- **Docs are always kept up to date.** ANY change - not only to functions - that alters observable behavior, structure, configuration, data, workflow, or usage MUST update the corresponding docs page in the SAME change; a change that touches a documented surface without updating its page is incomplete. Map the change to its page: functions -> `modules/<module>.md`; `Configuration.psd1` schema/placeholders -> `configuration/configuration-reference.md` (+ `placeholder-system.md` / `machine-types.md`); app/CSV lists -> `reference/software-list.md`; bootstrap/first-run flow -> `getting-started/*.md` (+ `modules/bootstrap.md`); AI prompts/agents/instructions -> `ai/agent-system.md` / `ai/overview.md`; failure modes -> `reference/troubleshooting.md`; page/module add/remove -> `_sidebar.md` + `docs_overview.md`. See `AGENTS.md` and `AI/Instructions/DocumentationStyle.md` for the full trigger lists.
- The docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH.
- `README.md` at the repo root is now a MINIMAL pointer (logo + intro + demo-video placeholder + link to the docs). It carries NO function reference. NEVER add `#### [Name]` function entries, a function Table of Contents, or per-function content to README, and do NOT update README when a function changes.
- The function reference lives in `docs/modules/<module>.md`: ONE man-style entry per function = a `## [FunctionName](<github-source-url>)` heading parsed by `List-Functions`, followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block (Description first, then Parameters / Usage / Alias as applicable; omit a bullet when not applicable). Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line. Entries are alphabetical within the page.
- After adding/renaming/removing a function: update its entry alphabetically in `modules/<module>.md`, update the module `.psd1` `FunctionsToExport`, and run `List-Functions -ListDiscrepancies` (must report none).
- Fork-only (Custom area) functions use the same entry format in `docs/custom/<module>.md`; they have no `FunctionsToExport` line (the `Custom` module exports them).
- `docs/docs_overview.md` is the internal maintenance reference (process + per-module index). `_sidebar.md` changes only when adding/removing a page.
- Use GENERICIZED example values in docs (placeholders like MyProject, MyRepo, GroupName, Work-PC) - no real personal/work identifiers.
- Never use em-dashes (the em-dash character, U+2014); always use a plain hyphen `-` instead, everywhere.
- ERASE any stale guidance describing the OLD model: README `#### [Name]` entries, README Table-of-Contents anchors for functions, the docs "## Overview" function table + "### FunctionName" per-function sections, and "keep README and docs in sync" instructions. Module pages now use `## [Name](url)` man-style entries, not `### Name` sections or Overview tables.

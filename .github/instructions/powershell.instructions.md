---
description: "Use when writing, modifying, or reviewing PowerShell functions, modules, manifests, or profile scripts. Covers module structure, naming conventions, parameter patterns, and Configuration.psd1 access."
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1"
---

# PowerShell Conventions

Read and follow these instruction files before generating or modifying PowerShell code:

- `AI/Instructions/PowerShellConventions.md` - Module structure, function naming, parameter patterns, error handling, adding new functions checklist
- `AI/Instructions/OutputFormatting.md` - Function signatures, comment-based help format, console output colors, config entry format
- `AI/Instructions/ConfigurationPatterns.md` - How to add/modify entries in Configuration.psd1, placeholder system, data patterns

**Never use em-dashes** (the em-dash character, U+2014) in code, comments, help text, string literals, or log messages; always use a plain hyphen `-`. The only exception is the browser-title regex classes (`BrowserGroups` in `Configuration.psd1`, `WindowTitle` in `Window/Layouts/*`).

## Documentation (single source of truth: `docs/`)

Since the 2026-06 documentation refactor, the docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH for the function reference. **Do NOT touch `README.md` for function documentation.**

`README.md` at the repo root is now a MINIMAL pointer (logo + intro + demo-video placeholder + link to the docs). It carries NO function reference. NEVER add `#### [Name]` function entries, a function Table of Contents, or per-function content to README, and do NOT update README when a function changes.

The function reference lives in `docs/modules/<module>.md` (`application.md`, `bootstrap.md`, `configuration.md`, `git.md`, `helper.md`, `system.md`, `tests.md`, `window.md`, `workflow.md`). Each function is ONE man-style entry:

- A `## [FunctionName](<github-source-url>)` heading, followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block - Description first, then Parameters / Usage / Alias as applicable (omit a bullet when not applicable).
- Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line.
- Entries are alphabetical within the page. Use GENERICIZED example values (placeholders like MyProject, MyRepo, GroupName, Work-PC) - no real personal/work identifiers.

These are man-style `## [Name](url)` entries - NOT a `## Overview` function table and NOT `### Name` per-function sections.

### Adding / renaming / removing a function

1. Update its entry alphabetically in `docs/modules/<module>.md`.
2. Update the module `.psd1` `FunctionsToExport`.
3. Run `List-Functions -ListDiscrepancies` (Helper module) - it PARSES the module pages and must report none.

Fork-only functions (not yet upstreamed) live under `Modules/Custom/<Module>/Functions/` with no `.psd1` entry (the `Custom` module exports them) and are documented in `docs/custom/<module>.md` using the same entry format. See `Windows/PowerShell/Modules/Custom/README.md`.

`docs/docs_overview.md` is the internal maintenance reference (process + per-module index). `_sidebar.md` changes only when adding/removing a page.

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

See `AGENTS.md` for the full critical operations policy.

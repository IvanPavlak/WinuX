# Documentation Style

> **Purpose**: Conventions for the Docsify documentation site at `docs/`.

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## Site Architecture

- **Framework**: Docsify v4 with `docsify-themeable` (dark/light toggle)
- **Sidebar**: `_sidebar.md` - manually maintained, `sidebarDisplayLevel: 1`, `subMaxLevel: 3`
- **Syntax highlighting**: Prism.js - PowerShell, Bash, JSON, YAML
- **Custom CSS classes**: `.function-signature`, `.badge`, `.badge-module`, `.badge-alias`, `.tip`, `.warning`, `.note`
- **Plugins**: search, copy-code, pagination, tabs

## Page Structure by Type

### Module Page (`modules/<name>.md`)

Module pages are the authoritative function reference. Each exported function is documented as ONE man-style entry: a `## [FunctionName](<github-source-url>)` heading followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block. Description comes first, then Parameters / Usage / Alias as applicable (omit a bullet when not applicable). Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line. Entries are alphabetical within the page.

````markdown
# Module Name Module

Brief 1-2 sentence description with **bold emphasis** on primary purpose.

## [Function-Name](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/<Module>/Functions/Function-Name.ps1)

- **Description:** One-paragraph behavioral description. Mention cross-function interactions, recovery paths, and side effects.
- **Parameters:** -Param1, -Param2, -SwitchParam
- **Usage:** Function-Name, Function-Name -Param1 "value"
- **Alias:** alias (only if one exists)

Optional human-only prose paragraph for additional context.

| Parameter | Type   | Required | Description  |
| --------- | ------ | -------- | ------------ |
| Param1    | String | Yes      | What it does |

​```powershell

# Basic usage

Function-Name -Param1 "value"
​```

**See also:** [Related-Function](#related-function)
````

Bullet-block rules:

- The `- **Key:** value` bullets must form a single contiguous block directly under the heading (no blank lines between them) - `List-Functions` parses this block.
- `**Description:**` is prose, not nested bullets. It should be detailed enough that a reader does not need to open the source file for high-level understanding.
- `**Parameters:**` is a comma-separated list of parameter names (with `-` prefix), optionally annotated like `-Exclude (wildcard/regex patterns)`. A full parameter table, if needed, goes below a blank line.
- `**Usage:**` lists 1-N comma-separated example invocations.
- Omit `**Alias:**` entirely when the function has no alias.
- The heading link target is the function's source file on GitHub.

### Getting Started / Configuration Page

- Step-by-step numbered sections
- Tables for requirements and reference data
- Before/after comparison tables where applicable
- "Next Steps" link at the bottom connecting to next page in sequence

### Reference Page (`reference/*.md`)

- Grouped tables by category
- Columns match the data type (aliases: `Alias | Function | Example`, functions: `Function | Key Parameters | Description`)

## Callout Boxes

Use GitHub-style Docsify callouts:

```markdown
> [!NOTE]
> Informational content

> [!TIP]
> Helpful suggestion

> [!WARNING]
> Important caution
```

## Cross-References

- Use relative markdown links: `[System module](../modules/system.md)`
- Use `relativePath: true` - no leading `/` needed in page content
- Sidebar uses `/`-prefixed paths (e.g., `/modules/application.md`)

## Configuration Examples

When showing `Configuration.psd1` entries, use PowerShell fenced code blocks:

```powershell
ProjectActions = @{
    NewProject = @(
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
    )
}
```

## Diagrams

Use ASCII art in fenced code blocks for architecture or flow visualization. No Mermaid - Docsify doesn't have the plugin configured.

## Source of Truth

- The docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH.
- Module pages (`modules/<module>.md`) are the authoritative function reference - the man-style `## [FunctionName](url)` entries are parsed by `List-Functions`.
- `docs_overview.md` is the internal maintenance reference (documentation process + per-module index), NOT the function reference.
- PowerShell comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`) is the primary upstream source; docs derive from it.

## Keep Docs Current (all pages, not just functions)

Docs must always reflect the current system. Every change to a documented surface updates its page in the SAME change - docs are never deferred. Function reference is the most common case, but the mandate applies to every page. Map the change to its page:

| Change                                                                              | Page(s) to update                                                                |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Exported function added/renamed/removed, or its behavior/parameters change          | `modules/<module>.md` (+ module `.psd1` `FunctionsToExport`, `docs_overview.md`) |
| Fork-only (Custom area) function added/renamed/removed, or its behavior changes     | `custom/<module>.md` (+ `Custom.psd1` `FunctionsToExport`; same man-style format) |
| `Configuration.psd1` key added/renamed/removed, placeholder change                  | `configuration/configuration-reference.md` (+ `placeholder-system.md`)           |
| New machine type or detection change                                                | `configuration/machine-types.md`                                                 |
| App/package list or any `Data/` CSV change                                          | `reference/software-list.md`                                                     |
| Bootstrap step, ordering, package manager, or first-run behavior change             | `getting-started/*.md` (+ `modules/bootstrap.md`)                                |
| Prompt / agent / instruction / provider / template under `AI/` or `.github/` change | `ai/agent-system.md`, `ai/overview.md`                                           |
| New failure mode, gotcha, or workaround                                             | `reference/troubleshooting.md`                                                   |
| Page or module added/removed                                                        | `_sidebar.md`, `docs_overview.md`                                                |

When in doubt whether a change is user-facing, assume it is and update the matching page. A change that touches a documented surface without updating its page is incomplete.

## Adding Documentation

1. Add the new page file in the appropriate directory
2. Update `_sidebar.md` only when adding/removing a page (maintain existing indentation/grouping)
3. Cross-reference from related pages where relevant

When adding/renaming/removing a function:

1. Add/update/remove its man-style entry alphabetically in `modules/<module>.md`
2. Update the module `.psd1` `FunctionsToExport`
3. Run `List-Functions -ListDiscrepancies` (must report none)
4. Update `docs_overview.md`'s per-module index if the function set changed

Fork-only (Custom area) functions follow the same steps except: the entry lives in
`custom/<module>.md`, and the `FunctionsToExport` update is to `Custom.psd1` (the fork-owned
manifest) rather than an engine module's.

## README.md (Root) - Minimal Pointer Only

`README.md` at the repository root is a MINIMAL pointer (logo + intro + demo-video placeholder + link to the docs). It carries NO function reference.

- NEVER add `#### [Name]` function entries, a function Table of Contents, or any per-function content to `README.md`.
- Do NOT update `README.md` when a function changes. The function reference lives exclusively in `docs/modules/<module>.md`.

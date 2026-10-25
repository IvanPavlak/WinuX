---
name: document
description: Write or update the documentation of a WinuX PowerShell function (the Windows half under Windows/PowerShell/Modules) from its code - the man-style entry on its module page and its configuration guide - and keep the module manifest and indexes in step. Use when the user says "document", adds, renames, removes or changes an exported function, or asks to bring a module page or guide in line with the code.
argument-hint: "Function name or module (e.g., 'Open-Browser' or 'Workflow')"
---

# Document a WinuX function

The docs under `docs/` are the single source of truth for WinuX's functions, and the `Infrastructure` tests check them against the code. Write from the code, never from memory. The conventions live in `AI/Instructions/DocumentationStyle.md`; read it first.

## 1. Read the function

- The source `Windows/PowerShell/Modules/<Module>/Functions/<Function>.ps1`: its comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`) is the primary source, and its body is what the docs must match. The help can lag: when it disagrees with the code, fix the help first.
- Whether it reads configuration: it does when the body references `Get-ConfigSetting`, `$global:Configuration`, `$Configuration.`, `Test-ConfigValue`, `Confirm-ConfigValue` or `$global:MachineSpecificPaths`, calls `Import-AppCsv`, reads a `Data/*.csv`, or writes `Configuration.psd1` through `Find-ConfigurationSection`. A reference only in a `.EXAMPLE` does not count.
- The module manifest `Windows/PowerShell/Modules/<Module>/<Module>.psd1`: an exported function is listed in `FunctionsToExport`. A fork-only function lives under `Modules/Custom/<Module>/` and is listed in `Custom.psd1`.

## 2. The module page entry

On `docs/modules/<module>.md` (a fork-only function: `docs/custom/<module>.md`), one entry per function, alphabetical:

- `## [Function-Name](https://github.com/<owner>/<repo>/blob/master/Windows/PowerShell/Modules/<Module>/Functions/Function-Name.ps1)`
- right under it, a contiguous bullet block: `- **Description:**` first (prose detailed enough that a reader does not need the source, with cross-function interactions), then `- **Parameters:**` (comma-separated, `-` prefixed), `- **Usage:**` (1-N invocations), `- **Alias:**` only when the profile defines one; omit a bullet that does not apply
- optional prose, a parameter table, examples and a `**See also:**` line after a blank line

`List-Functions` parses this block, so keep it contiguous.

## 3. The configuration guide

Every exported function has exactly one guide, `docs/configuration/guides/<module>/<Function-Name>.md`, listed in that folder's `README.md`. Use the FULL template of `DocumentationStyle.md` when the function reads configuration (every key it reads in `## Configuration Keys`, the fixed headings in order, three sub-bullets per decision), the STUB template otherwise, with its sentinel sentence verbatim. Generic example values only (`MyProject`, `Work-PC`, `C:\Users\You`), never a value from `Configuration.local.psd1`.

## 4. Keep the rest in step

- Added, renamed or removed function: `FunctionsToExport`, the guide file and its index row, `docs/docs_overview.md`, and a test file `Windows/PowerShell/Modules/Tests/Modules/<Module>/<Function>.Tests.ps1`.
- A removed or renamed function, parameter or configuration key goes through the deprecation policy of `VERSIONING.md` first: a warning wrapper or alias, `### Deprecated` in `CHANGELOG.md` and the `Deprecated` map of `ContractBaseline.json`.
- A changed configuration key: `docs/configuration/configuration-reference.md` and the guide of every function that reads it.
- Links are relative and checked; anchors follow docsify (lower case, punctuation dropped, spaces become hyphens).
- No em-dashes anywhere: a plain hyphen.

## 5. Hand over the checks

Do not run the tests yourself. Give the user the commands that check what changed: `Run-Tests -TestName "<Function>"` for the function's own tests and `Run-Tests -TestName "Infrastructure"` for the documentation, manifest and contract gates, and ask them to report failures. `List-Functions -ListDiscrepancies` must report none.

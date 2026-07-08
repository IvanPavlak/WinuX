# Output Formatting Conventions

> **Purpose**: Standards for formatting code, configuration entries, and documentation output in this repository.

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## Dashes: never use em-dashes

Never use the em-dash character (Unicode U+2014) anywhere: not in prose, documentation, code comments, log messages, string literals, or commit messages. Always use a plain hyphen `-` instead. The em-dash character must not appear in any managed file.

The only permitted exception is inside the regex character classes that match browser window titles (Firefox renders its title with an em-dash): the `BrowserGroups` patterns in `Configuration.psd1` and the `WindowTitle` patterns in `Window/Layouts/*`. Do not remove the em-dash there; it is required to match real windows.

## PowerShell Function Signatures

### Comment-Based Help

Every exported function should have comment-based help **inside** the function body, before the `param()` block:

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        One-line summary of what the function does.

    .DESCRIPTION
        Detailed description. Include:
        - What it does
        - When to use it
        - Side effects (if any)

    .PARAMETER ParamName
        Parameter description.

    .EXAMPLE
        Verb-Noun -ParamName "Value"
        Description of what this example does.
    #>
    [CmdletBinding()]
    param(
        ...
    )
}
```

If the function does not yet have comment-based help, omit it rather than adding generic placeholders - help should be meaningful or absent.

### Parameter Block Style

```powershell
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RequiredParam,

    [Parameter(Mandatory = $false)]
    [int]$OptionalWithDefault = 3,

    [Parameter()]
    [switch]$SwitchParam
)
```

Rules:

- `[Parameter(Mandatory = $true)]` for required params - use `$true`/`$false`, not shorthand
- `[Parameter()]` for optional params - include the attribute even if empty
- One blank line between parameter groups if logical grouping helps readability
- `[CmdletBinding()]` before `param()` for advanced function features
- Switches never have default values
- **Do not add a per-function debug switch.** Diagnostic output uses `Write-LogDebug`, which is gated
  globally by `Set-LogLevel` (see Console Output below) - no per-function switch or parameter threading.

### Console Output Style

Console output goes through the **Logging module** (`Write-Log*` functions). Use the wrappers -
**not** raw `Write-Host` - for all new and migrated code. Pass the message text only; the engine
adds the leading `` `n ``, the `[ ]` title brackets, and the `=> ` result prefix.

```powershell
# Section header / title (DarkCyan)  ->  "`n[Title]"
Write-LogTitle "Kill All"

# Plain step / progress (White)      ->  "`nMessage"   (leading-space indentation preserved)
Write-LogStep "Opening training file..."

# Success (Green)                     ->  "`n=> Message"
Write-LogSuccess "Operation completed successfully!"

# Warning (Yellow)                    ->  "`n Message"   (leading space, NO "=>")
Write-LogWarning "Project terminals are already open!"

# Error (Red)                         ->  "`n=> Message"   (also logged verbosely to the error log)
Write-LogError "No solution file found!"
try { ... } catch { Write-LogError "Build failed: $($_.Exception.Message)" -Exception $_ }

# Diagnostic / verbose-only (DarkCyan by default)  ->  "`n [Caller] Message"
Write-LogDebug "Captured $($handles.Count) window handle(s)"
Write-LogDebug "Using machine-specific layout => [$file]" -Style Success   # keep a former green debug line green
```

Conventions:

- The engine adds the `` `n `` leading newline - do **not** embed it in the message.
- For a blank line AFTER a message (e.g. to separate a header from the body that follows it), pass
  `-BlankLineAfter` - do **not** embed a trailing `` `n `` in the message. Example:
  `Write-LogTitle "Reloading Custom Modules" -BlankLineAfter`.
- `=>` is the result prefix for **success and error** messages (added by the engine). Warnings render
  with a single leading-space indent and **no** `=>`.
- Titles are `[Bracketed]` in DarkCyan; pass the bare title text.
- Include context in error messages: what failed and what's expected. Pass `-Exception $_` in
  `catch` blocks so the failure is recorded verbosely in the error log.
- `Write-LogDebug` is the verbose-gated diagnostic. It prints only when verbose logging is active. Use
  `-Style` to render the diagnostic in another level's color.

#### Verbosity

Control diagnostic visibility with the global level:

```powershell
Set-LogLevel Verbose            # show Write-LogDebug output for the rest of the session
Set-LogLevel Normal             # default: hide debug; show Title/Step/Success/Warning/Error
Set-LogLevel Quiet              # show only Warning/Error
Set-LogLevel Verbose { Kill-All }   # scoped: verbose for that command + everything it calls, then restored
```

`Set-LogLevel` is the cross-module control (module scope boundaries make a per-command `-Verbose`
unreliable for nested calls; a global `$VerbosePreference = 'Continue'` is also honored). File
logging always records every level regardless of console verbosity.

#### Raw `Write-Host` exceptions

A few call sites must keep raw `Write-Host` and are exempt from migration: the cold-start
`Install-Bootstrap.ps1` (runs before modules exist), the carriage-return spinner animation in
`Loading-Spinner`, and the chained `-NoNewline` menu rendering in `Resolve-Selection`. The
underlying color/format spec for those (and for the engine itself) is: Success/Error => `` `n=> `` in
Green/Red, Warning => `` `n `` (leading space, no `=>`) in Yellow, Info/Step = White, Title = DarkCyan
`[ ]`, Debug = DarkCyan `[Name]`.

## Configuration.psd1 Entries

### Header Comment Style

Sections in Configuration.psd1 use this header format:

```powershell
# ==============================================================================
# SECTION NAME
# ==============================================================================
# Brief description of what this section configures
# → Consumer: FunctionName (which function reads this)
```

### Entry Formats

**Simple key-value:**

```powershell
DefaultBrowser = "Firefox"
DefaultLocale = "hr-HR"
```

**Path with placeholders:**

```powershell
FastFetch = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
OhMyPosh = "{RepoRoot}\Windows\Oh-My-Posh\WinuX_{MachineType}.omp.json"
```

**List:**

```powershell
Workspaces = @(
    "Default", "WinuX", "Research", "Server", "Trading"
)
```

**Action sequence:**

```powershell
WorkspaceActions = @{
    WorkspaceName = @(
        @{ Action = "Open-Project"; Parameters = @{ Project = "ProjectName" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Group1", "Group2") } }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "WorkspaceName" } }
    )
}
```

**Hierarchical with Path/Target leaves:**

```powershell
SymbolicLinks = @{
    AppName = @{
        Path   = "{User}\path\to\link"
        Target = "{RepoRoot}\path\to\source"
    }
    AppWithMultiple = @{
        Component1 = @{
            Path   = "{User}\path\to\link1"
            Target = "{RepoRoot}\path\to\source1"
        }
        Component2 = @{
            Path   = "{User}\path\to\link2"
            Target = "{RepoRoot}\path\to\source2"
        }
    }
}
```

## Documentation Markdown

Since the 2026-06 documentation refactor, the docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH. `README.md` at the repo root is now a MINIMAL pointer (logo + intro + demo-video placeholder + link to the docs). It carries NO function reference - NEVER add `#### [Name]` function entries, a function Table of Contents, or per-function content to README, and do NOT update README when a function changes.

### Function Reference Entries

The function reference lives in `docs/modules/<module>.md`. Each function is ONE man-style entry: a `## [FunctionName](<github-source-url>)` heading followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block. Order the bullets Description first, then Parameters / Usage / Alias as applicable; omit a bullet when it does not apply.

```markdown
## [Verb-Noun](https://github.com/Owner/MyRepo/blob/master/Windows/Modules/MyModule/Verb-Noun.ps1)

- **Description:** Brief summary of what the function does.
- **Parameters:** `-RequiredParam` `[-OptionalParam]` `[-SwitchName]`
- **Usage:** `Verb-Noun -RequiredParam "Value"`
- **Alias:** `vn`
```

- Required params without brackets
- Optional params in `[-brackets]`
- Switch params as `[-SwitchName]`
- Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line
- Entries are alphabetical within the page
- Use genericized example values (placeholders like MyProject, MyRepo, GroupName, Work-PC) - no real personal/work identifiers

### Keeping the Reference Consistent

`List-Functions` (Helper module) PARSES these module pages. After adding, renaming, or removing a function: update its entry alphabetically in `modules/<module>.md`, update the module `.psd1` `FunctionsToExport`, and run `List-Functions -ListDiscrepancies` (must report none).

`docs/docs_overview.md` is the internal maintenance reference (process + per-module index). `_sidebar.md` changes only when adding or removing a page.

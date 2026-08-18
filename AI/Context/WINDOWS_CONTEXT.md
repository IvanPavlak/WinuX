# Windows Context - Full Function Reference

> **Purpose**: Deep reference for the Windows PowerShell system. Covers all modules, functions, parameters, and configuration patterns.
> **Last updated**: 2026-03-24

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## 📌 Authoritative Function Reference: `docs/modules/*.md`

The AUTHORITATIVE, always-current function reference is now `docs/modules/<module>.md` - man-style entries (one `## [FunctionName](<source-url>)` heading per function, followed by a contiguous `- **Key:** value` bullet block) that `List-Functions` parses directly. The docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH.

**This context document is a convenience snapshot that may lag the actual code.** When the listing below and a module page disagree, DEFER to the module page. Do not rewrite or expand the full function listing here; consult `docs/modules/*.md` for authoritative, up-to-date details.

## Module Architecture

Each module follows the same pattern:

```
ModuleName/
├── ModuleName.psd1      # Manifest (version, dependencies, FunctionsToExport)
├── ModuleName.psm1      # Loader (dot-sources all .ps1 files, exports functions)
└── Functions/
    ├── FunctionA.ps1    # One function per file
    └── FunctionB.ps1
```

The `.psm1` loader pattern:

```powershell
$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"
$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")
foreach ($Function in $Functions) { . $Function.FullName }
$Functions | ForEach-Object { Export-ModuleMember -Function $_.BaseName }
```

## Global State

| Variable                       | Set By                   | Contents                                     |
| ------------------------------ | ------------------------ | -------------------------------------------- |
| `$global:Configuration`        | `Load-PathConfiguration` | Full Configuration.psd1 hashtable (expanded) |
| `$global:MachineType`          | `DetermineMachineType`   | "PC", "Laptop", "Work", or "Test"            |
| `$global:MachineSpecificPaths` | `Load-PathConfiguration` | Machine-specific expanded path mappings      |

---

## Function Reference

The full, current function reference - every function with its parameters, usage, and aliases - lives in the per-module docsify pages and is parsed by `List-Functions`. Those pages are the single source of truth; this context file intentionally does NOT duplicate the function lists, to avoid drift.

- `docs/modules/`: `application.md`, `bootstrap.md`, `configuration.md`, `git.md`, `helper.md`, `system.md`, `window.md`, `workflow.md`, `tests.md`

For an in-session view, run `List-Functions` or `List-Functions -Category <Module>`; `List-Functions -ListDiscrepancies` confirms the docs match the loaded functions.

---

## Configuration.psd1 Section Reference

### Sections and Their Consumers

| Section                       | Consumer Function(s)            | Data Pattern                         |
| ----------------------------- | ------------------------------- | ------------------------------------ |
| `Universal`                   | Profile, all modules            | Constants: paths, URLs, browser defs |
| `BasePaths`                   | `Expand-ConfigPaths`            | Per-machine root dirs                |
| `PathTemplates`               | `Expand-ConfigPaths`            | Placeholder-based paths              |
| `MachineTypes`                | `DetermineMachineType`          | Hostname→type mapping                |
| `BrowserGroups`               | `Open-Browser`                  | Hierarchical URL groups              |
| `Workspaces`                  | `Open-Workspace`                | Workspace name list                  |
| `WorkspaceActions`            | `Open-Workspace`                | Action sequences per workspace       |
| `Projects`                    | `Open-Project`                  | Project name list                    |
| `ProjectActions`              | `Open-Project`                  | Action sequences per project         |
| `RunnableProjects`            | `Run-Project`                   | Projects with run commands           |
| `TerminalTabs`                | `Open-ProjectTerminals`         | Terminal configs per project         |
| `SymbolicLinks`               | `SymbolicLinkMaker`             | Path→Target recursive mappings       |
| `WindowLayouts`               | `Set-WorkspaceWindowLayout`     | Per-workspace window rules           |
| `Repositories`                | `Update-Repositories`           | Git repo paths                       |
| `Applications` / `WingetApps` | `Install-WingetApps`            | Software install list                |
| `Theme`                       | `Set-SystemTheme`               | Per-machine theme config             |
| `Wallpaper`                   | `Set-Wallpaper`                 | Per-machine wallpaper paths          |
| `PostgreSqlPasswords`         | `Configure-PostgreSqlPasswords` | DB credentials                       |
| `WakeOnLan`                   | `Send-WakeOnLan`                | Machine MAC addresses                |
| `PowerButtonActions`          | `Set-PowerButtonActions`        | Per-machine power config             |

### Data Patterns

**Browser Groups** - hierarchical, unlimited nesting:

```powershell
BrowserGroups = @(
    @{ Simple = @("https://example.com") }
    @{ Named = @( @{ Name = "Label"; Url = "https://..." } ) }
    @{ Nested = @( @{ Child = @( @{ Name = "..."; Url = "..." } ) } ) }
)
```

**Workspace/Project Actions** - sequential action lists with parameter forwarding:

```powershell
WorkspaceActions = @{
    Name = @(
        @{ Action = "FunctionName"; Parameters = @{ Key = "Value" } }
        @{ Action = "Return" }  # Special: stops processing
    )
}
```

Parameter substitution: `{ProjectName}` is replaced with actual project name.
Parameter forwarding: `Get-FilteredParams` passes command-line args only to functions that accept them.

**Symbolic Links** - recursive hashtable:

```powershell
SymbolicLinks = @{
    App = @{
        Path   = "{User}\target\path"
        Target = "{RepoRoot}\source\path"
    }
    AppWithComponents = @{
        Component1 = @{ Path = "..."; Target = "..." }
        Component2 = @{ Path = "..."; Target = "..." }
    }
}
```

**Terminal Tabs** - per-project tab definitions:

```powershell
TerminalTabs = @{
    ProjectName = @(
        @{ Title = "TabName"; Path = "DEFAULT" }      # Project root dir
        @{ Title = "WSL"; Path = "WSL" }               # WSL session
        @{ Title = "API"; Path = "{ProjectKey}\api" }  # Subdir
    )
}
```

## Testing Infrastructure

- **Framework**: Pester
- **Location**: `Modules/Tests/Modules/`
- **Coverage**: one `*.Tests.ps1` file per function under `Modules/Tests/Modules/<Module>/`
- **Run**: `Run-Tests [-TestName] [-Path] [-Detailed] [-PassThru]`
- **Verifying a change (agents)**: do NOT run the suite yourself - ask the developer to run the scoped command and report failures:
    - Just what changed (preferred): `Run-Tests -TestName "<ChangedFunctionOrPattern>"`
    - Everything (broad changes): `Run-Tests`
- **Tested Dependencies** (source of truth: the `TESTED VERSIONS` block in `Modules/Bootstrap/Data/WinGetApps.csv`):
    - Microsoft.PowerToys `0.100.2` (pinned by its WinGetApps.csv row)
    - VirtualDesktop PS module `1.5.11` (pinned via `$pinnedModules` in `Install-PowerShellModules.ps1`)
    - Pester (pinned repo-wide in `Modules/Tests/RequiredPesterVersion.txt`; the test harness, `Install-PowerShellModules`, and CI all read that one file)
    - PowerShell `7.6.4` (not enforced; last tested)
    - Windows `25H2` (build 26200; not enforced)

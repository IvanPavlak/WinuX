# PowerShell Conventions

> **Purpose**: Coding standards for all PowerShell code in this repository.

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## Module Structure

Every module follows this layout:

```
ModuleName/
├── ModuleName.psd1      # Manifest - version, dependencies, FunctionsToExport
├── ModuleName.psm1      # Loader - dot-sources .ps1 files, exports functions
└── Functions/
    └── FunctionName.ps1 # One function per file, filename = function name
```

### Manifest (.psd1)

```powershell
@{
    ModuleVersion     = "1.0"
    Author            = "Ivan Pavlak"
    RootModule        = "ModuleName.psm1"
    RequiredModules   = @('Helper')  # Only list actual dependencies
    FunctionsToExport = @(
        'Function-One',
        'Function-Two'
    )
}
```

- `FunctionsToExport` must list every exported function explicitly - no wildcards
- `RequiredModules` only for modules this module directly depends on
- Adding a new function requires updating `FunctionsToExport`

### Loader (.psm1)

Standard loader pattern - do not modify:

```powershell
$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"
$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")
foreach ($Function in $Functions) {
    . $Function.FullName
}
$Functions | ForEach-Object {
    $FunctionName = $_.BaseName
    Export-ModuleMember -Function $FunctionName
}
```

## Function Naming

- Use `Verb-Noun` format: `Open-Browser`, `Set-Wallpaper`, `Test-AdminPrivileges`
- File name must match function name: `Open-Browser.ps1` contains `function Open-Browser`
- Use PowerShell approved verbs where possible (`Get-Verb` to list)
- Exceptions exist in this repo for readability (e.g., `GitBranch`, `GitPull`, `Countdown`, `SymbolicLinkMaker`) - match existing style when extending these
- Never define nested functions. If a helper is needed, extract it into its own top-level function file or a separate helper script and dot-source/import it where needed.

## Function Patterns

### Configuration Access

Access configuration via `$Configuration` (the expanded global):

```powershell
$browserConfig = $Configuration.Universal.Browsers[$Browser]
$wolConfig = $Configuration.WakeOnLanConfig
$urlGroups = $Configuration.BrowserGroups
```

### Selection/Menu Pattern

Use `Resolve-Selection` for interactive choices:

```powershell
$resolveParams = @{
    InputObject              = $InputFromUser
    OptionList               = $Configuration.SomeList
    MenuTitle                = "[Available Options]"
    PromptMessage            = "Select option (Press Enter for default => $default)"
    AllowEmptyPromptResponse = $true
    AllowMultipleSelections  = $true
}
$selection = Resolve-Selection @resolveParams
```

### Application Launcher Pattern

Use `Start-Application` for launching apps:

```powershell
function Open-AppName {
    Start-Application -AppName "AppName" `
        -ProcessName "appname" `
        -StartMethod "ConfigPath" `
        -ConfigKey "AppNameExe"
}
```

StartMethod options: `ConfigPath`, `DirectPath`, `PackageName`, `UWP`

### Error Handling

```powershell
# Configuration validation
if (-not $config) {
    Write-LogError "ConfigKey not found in configuration!"
    return
}

# Try/catch for operations
try {
    # operation
    Write-LogSuccess "Success message!"
}
catch {
    Write-LogError "Error: $($_.Exception.Message)" -Exception $_
}
```

- Return early on missing config (don't throw, don't continue with bad state)
- Catch and display errors with context
- Use `$_.Exception.Message` for error text

### Diagnostic / Verbose Output

Emit diagnostics with `Write-LogDebug` (from the Logging module). It is verbose-gated - it prints to
the console only when verbose logging is active and is always recorded to the file log:

```powershell
Write-LogDebug "Captured $($handles.Count) window handle(s)"

# Guard expensive debug-only work with Test-LogVerbose
if (Test-LogVerbose) {
    $detail = Get-ExpensiveDiagnostic
    Write-LogDebug "Resolved layout => [$detail]"
}
```

Turn verbose output on globally with `Set-LogLevel Verbose`, or scope it to one command with
`Set-LogLevel Verbose { Verb-Noun }`. There is no per-function debug switch.

## Parameter Conventions

- `[switch]$Override` - force/skip checks
- `[switch]$Auto` - use configuration defaults instead of prompting
- `[string[]]$Groups` / `[string[]]$Project` / `[string[]]$Machine` - accept multiple selections
- `[Parameter(Position = 0)]` - for the primary/most-used parameter
- `[Parameter(ValueFromRemainingArguments = $true)]` - catch extra args (used sparingly)

## Testing

- Test files live in `Modules/Tests/Modules/`
- Naming: `FunctionName.Tests.ps1`
- Framework: Pester
- Run via: `Run-Tests [-TestName "FunctionName"] [-Detailed]`
- **Agents:** do NOT run the suite yourself (no `Import-Module` + `Invoke-Pester`, no bootstrap scripts). After changing code or tests, give the developer the scoped command - `Run-Tests -TestName "<ChangedFunction>"` (or `Run-Tests` for broad changes) - and ask them to report failures
- Mock external dependencies (processes, file system, network)
- Test configuration-dependent functions with synthetic config hashtables
- Every new exported function should add corresponding tests in the same change whenever practical
- New tests should verify behavior outcomes and edge/failure paths, not `Write-Host`/message wording

## Adding or Modifying a Function

When you **add** a function:

1. Create `FunctionName.ps1` in the appropriate module's `Functions/` directory
2. Add `'FunctionName'` to the module's `.psd1` `FunctionsToExport` array (the manifest filters exports - a function missing here is NOT available even though the loader dot-sources it)
3. Follow existing patterns in that module for style consistency
4. If the function needs a profile alias, add it to `Microsoft.PowerShell_profile.ps1`
5. If it reads configuration, document the config section it consumes
6. Add or update meaningful Pester tests for the function in `Modules/Tests/Modules/<Module>/`, then ask the developer to run them (`Run-Tests -TestName "FunctionName"`) and report failures - do not run the suite yourself
7. **Update documentation in the same change - required, see below**

When you **modify** a function's behavior, parameters, or signature, do step 7 (and step 2 only if you renamed it).

### Documentation is not optional

The docsify docs under `docs/` are the SINGLE SOURCE OF TRUTH. `README.md` at the repo root is now a MINIMAL pointer (logo + intro + demo-video placeholder + link to the docs) - it carries NO function reference. NEVER add `#### [Name]` function entries, a function Table of Contents, or per-function content to README, and do NOT update README when a function changes.

Any function that is added, renamed, removed, or whose parameters or caller-visible behavior change MUST update these surfaces in the same change:

- `docs/modules/<Module>.md` - the function's man-style entry: a `## [FunctionName](<github-source-url>)` heading followed IMMEDIATELY by a contiguous `- **Key:** value` bullet block (Description first, then Parameters / Usage / Alias as applicable; omit a bullet when not applicable). Optional human-only prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line. Entries are alphabetical within the page.
- The module's `.psd1` `FunctionsToExport` - keep it in sync with the function's existence/name.
- After editing, run `List-Functions -ListDiscrepancies` (it PARSES the module pages) and confirm it reports none.

`docs/docs_overview.md` is the internal maintenance reference (process + per-module index); `_sidebar.md` changes only when adding/removing a page. Use genericized example values in docs (placeholders like MyProject, MyRepo, GroupName, Work-PC) - no real personal/work identifiers.

Keep entries consistent with the function's comment-based help, and mention new cross-function interactions in the entries of both functions involved. Exact formats live in `AI/Instructions/DocumentationStyle.md`. Treat skipped doc updates as an incomplete change - verify the function name appears in `modules/<Module>.md` and `FunctionsToExport`, and that `List-Functions -ListDiscrepancies` is clean, before considering the work done.

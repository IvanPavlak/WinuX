# Configuration Module

The Configuration module provides **reliable programmatic modification** of `Configuration.psd1` - adding browser groups, workspaces, projects, symbolic links, and window layouts without manual text editing.

## [Add-BrowserGroup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Add-BrowserGroup.ps1)

- **Description:** Adds a new browser URL group to the `BrowserGroups` array in `Configuration.psd1`. Supports named URLs with labels (recommended, via `-Urls`) and simple URL lists (via `-SimpleUrls`).
- **Parameters:** -GroupName, -Urls (hashtable[]), -SimpleUrls (string[]), -ConfigurationFilePath
- **Usage:** `Add-BrowserGroup -GroupName GroupName -Urls @(@{ Name = "GitHub"; Url = "https://github.com" })`, `Add-BrowserGroup -GroupName GroupName -SimpleUrls @("https://www.google.com/")`

Locates the `BrowserGroups` section via `Find-ConfigurationSection`, builds a correctly indented entry, and inserts it at the end of the section. The named (`-Urls`) and simple (`-SimpleUrls`) forms are mutually exclusive parameter sets, exactly one of which is required.

| Parameter                | Description                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------ |
| `-GroupName`             | Unique name for the browser group (positional, mandatory).                                       |
| `-Urls`                  | Array of URL hashtables `@{ Name = "Label"; Url = "https://..." }`. Mandatory for the named set. |
| `-SimpleUrls`            | Array of plain URL strings for groups without labels. Mandatory for the simple set.              |
| `-ConfigurationFilePath` | Override the `Configuration.psd1` path (for testing).                                            |

```powershell
# Named URLs (recommended) - labels appear in the Open-Browser menu
Add-BrowserGroup -GroupName GroupName -Urls @(
    @{ Name = "GitHub"; Url = "https://github.com" }
    @{ Name = "StackOverflow"; Url = "https://stackoverflow.com" }
)

# Simple URL list - no labels
Add-BrowserGroup -GroupName GroupName -SimpleUrls @("https://www.google.com/")
```

**See also:** [Open-Browser](application.md#open-browser)

## [Add-Project](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Add-Project.ps1)

- **Description:** Adds a project to `Configuration.psd1`. Appends the name to the `Projects` array, creates its `ProjectActions` entry, and optionally adds `TerminalTabs`, `ProjectTerminals`, and `RunnableProjects` entries. If no actions are given it creates default `Open-VSCode` + `Open-ProjectTerminals-Or-RunProject` actions.
- **Parameters:** -Name, -Actions, -TerminalTabs, -BasePath, -Paths, -Runnable, -ConfigurationFilePath
- **Usage:** `Add-Project -Name "MyProject"`, `Add-Project -Name "MyProject" -TerminalTabs @(@{ Title = "Root"; Path = "DEFAULT" }) -Runnable`

Edits `Configuration.psd1` in place by locating each section (`Projects`, `ProjectActions`, and optionally `TerminalTabs`, `RunnableProjects`, `ProjectTerminals`) and inserting the new lines. A `ProjectActions` entry is always created; the other sections are only touched when their corresponding parameters are supplied.

| Parameter                | Description                                                                                                                                  |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Name`                  | The project name (mandatory, positional). Added to the `Projects` array and used as the key for every other generated entry.                 |
| `-Actions`               | Array of action hashtables for `ProjectActions`. Omit to generate the default `Open-VSCode` + `Open-ProjectTerminals-Or-RunProject` actions. |
| `-TerminalTabs`          | Optional array of terminal tab hashtables, each `@{ Title = "..."; Path = "..." }`, added to the `TerminalTabs` section.                     |
| `-BasePath`              | Optional dot-notation base path for the `ProjectTerminals` entry (e.g. `"Projects.MyProject"`). Requires `-Paths`.                           |
| `-Paths`                 | Optional array of path names for the `ProjectTerminals` entry (e.g. `@("ROOT", "API")`). Requires `-BasePath`.                               |
| `-Runnable`              | If set, adds the project to `RunnableProjects`.                                                                                              |
| `-ConfigurationFilePath` | Override the `Configuration.psd1` path (for testing).                                                                                        |

```powershell
# Minimal: add the project with default Open-VSCode + Open-ProjectTerminals-Or-RunProject actions
Add-Project -Name "MyProject"

# Full project with custom actions, terminal tabs, project terminals, and runnable flag
Add-Project -Name "MyProject" -Actions @(
    @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "MySolution" } }
    @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } }
    @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "MyProject" } }
) -TerminalTabs @(
    @{ Title = "Root"; Path = "DEFAULT" }
    @{ Title = "API"; Path = "{ProjectName}\api" }
) -BasePath "Projects.MyProject" -Paths @("ROOT", "API") -Runnable
```

**See also:** [Add a New Project](../configuration/guides/add-new-project.md)

## [Add-SymbolicLink](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Add-SymbolicLink.ps1)

- **Description:** Adds a symbolic link entry to the `SymbolicLinks` section of `Configuration.psd1`. Supports both simple (single Path/Target) and nested (multiple files under one app) entries, preserving the file's indentation and key alignment.
- **Parameters:** -Name, -Path, -Target, -Links, -ConfigurationFilePath
- **Usage:** `Add-SymbolicLink -Name "MyApp" -Path "{AppData}\MyApp\config.json" -Target "{RepoRoot}\MyApp\config.json"`, `Add-SymbolicLink -Name "MyApp" -Links @(@{ Name = "Settings"; Path = "{AppData}\MyApp\settings.json"; Target = "{RepoRoot}\MyApp\settings.json" })`

Reads the current `Configuration.psd1`, locates the `SymbolicLinks` section via `Find-ConfigurationSection`, builds a new entry with correct indentation (keys aligned at 21 characters), and inserts it before the section's closing bracket. The `Simple` and `Nested` parameter sets are mutually exclusive: use `-Path`/`-Target` for a single link, or `-Links` for multiple files belonging to one app. Use placeholder tokens such as `{AppData}` and `{RepoRoot}` in paths so they resolve per machine.

| Parameter                | Description                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------- |
| `-Name`                  | Name for the symbolic link entry (typically the app name). Mandatory, positional.                       |
| `-Path`                  | The symlink path where the link should be created. Use placeholders. (Simple set)                       |
| `-Target`                | The actual file path that the link points to. Use placeholders. (Simple set)                            |
| `-Links`                 | Array of hashtables with `Name`, `Path`, and `Target` keys for nested, multi-file entries. (Nested set) |
| `-ConfigurationFilePath` | Override the `Configuration.psd1` path (for testing).                                                   |

```powershell
# Simple link: one file for one app
Add-SymbolicLink -Name "MyApp" `
    -Path "{AppData}\MyApp\config.json" `
    -Target "{RepoRoot}\MyApp\config.json"

# Nested links: multiple files for one app
Add-SymbolicLink -Name "MyApp" -Links @(
    @{ Name = "Settings"; Path = "{AppData}\MyApp\settings.json"; Target = "{RepoRoot}\MyApp\settings.json" }
    @{ Name = "Config";   Path = "{AppData}\MyApp\config.yaml";   Target = "{RepoRoot}\MyApp\config.yaml" }
)
```

## [Add-WindowLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Add-WindowLayout.ps1)

- **Description:** Creates a new window layout `.psd1` template file for a workspace under `Window/Layouts/{MachineType}/`. The generated template includes a basic monitor configuration and a sample layout entry that can be customized afterward. Optionally registers the workspace in `SimpleLayoutWorkspaces` in `Configuration.psd1` for layout-only switching with no window positioning.
- **Parameters:** -WorkspaceName, -MachineType, -Simple, -ConfigurationFilePath, -LayoutsDirectory
- **Usage:** `Add-WindowLayout -WorkspaceName "MyWorkspace"`, `Add-WindowLayout -WorkspaceName "MyWorkspace" -MachineType @("PC", "Laptop")`, `Add-WindowLayout -WorkspaceName "MyWorkspace" -Simple`

For each machine type, the function creates the `{MachineType}` subdirectory if needed and writes a `{WorkspaceName}_{MachineType}.psd1` template; existing layout files are left untouched (no overwrite). When `-MachineType` is omitted it defaults to the current machine's type from `Configuration.psd1` (falling back to `Test`). With `-Simple`, the workspace name is appended to the `SimpleLayoutWorkspaces` array in `Configuration.psd1`.

| Parameter                | Description                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `-WorkspaceName`         | The workspace name for the layout (positional, required).                                                    |
| `-MachineType`           | One or more machine types (`string[]`) to create layouts for. Defaults to the current machine type.          |
| `-Simple`                | Adds the workspace to `SimpleLayoutWorkspaces` in `Configuration.psd1` (layout-only, no window positioning). |
| `-ConfigurationFilePath` | Override the `Configuration.psd1` path (for testing).                                                        |
| `-LayoutsDirectory`      | Override the Layouts directory path (for testing).                                                           |

```powershell
# Create a layout for the current machine type
Add-WindowLayout -WorkspaceName "MyWorkspace"

# Create layouts for specific machine types
Add-WindowLayout -WorkspaceName "MyWorkspace" -MachineType @("PC", "Laptop")

# Simple layout (no window positioning) and register it in SimpleLayoutWorkspaces
Add-WindowLayout -WorkspaceName "MyWorkspace" -Simple
```

**See also:** [Add-Workspace](#add-workspace)

## [Add-Workspace](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Add-Workspace.ps1)

- **Description:** Adds a workspace to `Configuration.psd1`: appends the name to the `Workspaces` array and creates its `WorkspaceActions` entry. If no actions are specified, it creates a default `Set-WorkspaceWindowLayout` action for the workspace.
- **Parameters:** -Name, -Actions, -ConfigurationFilePath
- **Usage:** `Add-Workspace -Name "MyWorkspace"`, `Add-Workspace -Name "MyWorkspace" -Actions @(@{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } })`

| Parameter                | Description                                                                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Name`                  | The workspace name (mandatory, positional). Added to the `Workspaces` array.                                                                                                          |
| `-Actions`               | Array of action hashtables for `WorkspaceActions`, each `@{ Action = "FunctionName"; Parameters = @{ Key = "Value" } }`. Omit to create a default `Set-WorkspaceWindowLayout` action. |
| `-ConfigurationFilePath` | Override the `Configuration.psd1` path (used for testing).                                                                                                                            |

```powershell
# Add a workspace with custom actions
Add-Workspace -Name "MyWorkspace" -Actions @(
    @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName") } }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
)

# Add a workspace with the default Set-WorkspaceWindowLayout action only
Add-Workspace -Name "MyWorkspace"
```

## [ConvertTo-ActionString](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/ConvertTo-ActionString.ps1)

- **Description:** Converts an action hashtable into a properly formatted `Configuration.psd1` entry string for insertion into `WorkspaceActions` or `ProjectActions` sections. Handles array, boolean, and string parameter values.
- **Parameters:** -Action, -Indent
- **Usage:** `ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName") } } -Indent "\`t\`t\`t"` (internal use)

Internal helper used by the `Add-Workspace` and `Add-Project` functions to serialize action definitions. Given an action hashtable with an `Action` key and an optional `Parameters` key, it emits a single line in the exact shape used inside the `WorkspaceActions`/`ProjectActions` blocks of `Configuration.psd1`. Parameter values are rendered by type: arrays become `@("a", "b")`, booleans become `$true`/`$false`, and everything else is quoted as a string. The `-Indent` prefix is prepended so the line aligns with the surrounding section.

| Parameter | Description                                                                                   |
| --------- | --------------------------------------------------------------------------------------------- |
| `-Action` | The action hashtable, with an `Action` key and an optional `Parameters` hashtable. Mandatory. |
| `-Indent` | The indentation prefix prepended to the output string (e.g. a run of tabs). Mandatory.        |

```powershell
# Serialize an action that opens a browser group, indented three tabs deep
ConvertTo-ActionString -Action @{
    Action     = "Open-Browser"
    Parameters = @{ Groups = @("GroupName", "OtherGroup") }
} -Indent "`t`t`t"
# Output: @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName", "OtherGroup") } }
```

**See also:** [Add Workspace](../configuration/guides/add-new-workspace.md), [Add Project](../configuration/guides/add-new-project.md)

## [Find-ConfigurationSection](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Find-ConfigurationSection.ps1)

- **Description:** Finds a named section's boundaries in `Configuration.psd1`. Locates the section by name and returns its start/end line indices, indentation, and bracket type by tracking bracket depth while ignoring brackets inside strings and comments.
- **Parameters:** -Lines, -SectionName
- **Usage:** `Find-ConfigurationSection -Lines (Get-Content "Configuration.psd1") -SectionName "BrowserGroups"`

Internal helper used by the configuration-builder functions (`Add-BrowserGroup`, `Add-Workspace`, `Add-Project`, `Add-SymbolicLink`) to locate where to insert new entries. It handles every `Configuration.psd1` pattern: `@()` arrays, `@{}` hashtables, nested brackets, placeholder strings like `{Dev}`, and single-line arrays. Returns `$null` when the named section is not found.

| Parameter      | Description                                                                             |
| -------------- | --------------------------------------------------------------------------------------- |
| `-Lines`       | The file content as an array of strings (`string[]`); empty strings allowed.            |
| `-SectionName` | The configuration section name to find (e.g., `"BrowserGroups"`, `"WorkspaceActions"`). |

```powershell
# Locate a section's boundaries within Configuration.psd1
$lines = Get-Content "Configuration.psd1"
$section = Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"
# Returns @{ StartIndex = 1829; EndIndex = 2050; Indent = "`t"; BracketType = "(" }
```

**See also:** [Add Browser Group](../configuration/guides/add-browser-group.md)

## [Test-ConfigurationKeyPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Test-ConfigurationKeyPath.ps1)

- **Description:** Tests whether an ordered configuration key path resolves to a non-empty value. Walks a hashtable using the provided key path and returns `$true` only when every segment exists and the final resolved value is not `$null` or an empty string. Used internally by `Test-ConfigurationSchema` to validate required top-level and nested settings.
- **Parameters:** -Table, -Path
- **Usage:** `Test-ConfigurationKeyPath -Table $Configuration -Path @("GitConfig", "UserName")`

| Parameter | Description                                                                   |
| --------- | ----------------------------------------------------------------------------- |
| `-Table`  | Hashtable to inspect. Mandatory.                                              |
| `-Path`   | Ordered string array of key names to resolve within the hashtable. Mandatory. |

```powershell
# Returns $true when GitConfig.UserName exists and is not empty
Test-ConfigurationKeyPath -Table $Configuration -Path @("GitConfig", "UserName")
```

**See also:** [Test-ConfigurationSchema](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Test-ConfigurationSchema.ps1)

## [Test-ConfigurationSchema](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Configuration/Functions/Test-ConfigurationSchema.ps1)

- **Description:** Validates that all required keys are present in the loaded configuration. Checks the global `$Configuration` hashtable for the presence and non-null/non-empty values of every key required by core module functions, and reports each missing or empty key. In the default mode it writes warnings without throwing, so the shell can still start with a degraded configuration rather than failing entirely; with `-Strict` it throws a terminating error on the first set of missing keys, suitable for bootstrap or test fail-fast.
- **Parameters:** -Configuration, -Strict
- **Usage:** `Test-ConfigurationSchema`, `Test-ConfigurationSchema -Strict`, `Test-ConfigurationSchema -Configuration $myConfig`

Call this immediately after `Load-PathConfiguration` during the bootstrap or profile initialization sequence to surface typos and missing entries early. It validates required top-level keys and nested paths (machine detection, the path system, `GitConfig`, locale settings, and application keys such as `BrowserGroups`, `SymbolicLinks`, and `RepositoryGroups`), delegating each presence check to `Test-ConfigurationKeyPath`. If `$Configuration` is null, the function warns (or throws under `-Strict`) that `Load-PathConfiguration` may not have run.

| Parameter        | Description                                                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `-Configuration` | The configuration hashtable to validate. Defaults to `$global:Configuration`.                                                       |
| `-Strict`        | Throws a terminating error when any required key is missing. Use during bootstrap/testing; omit for profile startup (warning-only). |

```powershell
# Validate the global configuration; warn on each missing key
Test-ConfigurationSchema

# Fail fast during bootstrap or tests
Test-ConfigurationSchema -Strict

# Validate a specific configuration hashtable instead of the global one
Test-ConfigurationSchema -Configuration $myConfig
```

**See also:** [Configuration](../modules/configuration.md)

> [!TIP]
> All `/add-*` slash commands in Copilot Chat use these functions. You can use the functions directly or let Copilot guide you through the process.

## How It Works

All `Add-*` functions follow the same pattern:

1. **Read** the current `Configuration.psd1` content
2. **Find** the target section using `Find-ConfigurationSection` (bracket depth tracking)
3. **Build** the new entry string with correct indentation and key alignment
4. **Insert** the entry before the section's closing bracket
5. **Write** the modified content back to disk

Key alignment is preserved automatically - `WorkspaceActions` keys align at 24 characters, `ProjectActions` at 28 characters, and `SymbolicLinks` at 21 characters - matching the existing format.

## Testing

All functions are covered by Pester tests in `Modules/Tests/Modules/Configuration/`:

| Test File                             | Tests | Validates                                                                                             |
| ------------------------------------- | ----- | ----------------------------------------------------------------------------------------------------- |
| `Find-ConfigurationSection.Tests.ps1` | 7     | Hashtable/array finding, single-line arrays, string placeholders, nesting                             |
| `Add-BrowserGroup.Tests.ps1`          | 4     | Named URLs, simple URLs, valid format, error handling                                                 |
| `Add-Workspace.Tests.ps1`             | 4     | Name addition, actions, default action, valid format                                                  |
| `Add-Project.Tests.ps1`               | 8     | Basic, defaults, custom actions, TerminalTabs, ProjectTerminals, RunnableProjects, PathMappings, full |
| `Add-SymbolicLink.Tests.ps1`          | 4     | Simple link, preserve existing, nested links, valid format                                            |
| `Add-WindowLayout.Tests.ps1`          | 8     | File creation, multiple machines, no overwrite, valid data, SimpleLayoutWorkspaces                    |

Run tests with:

```powershell
Invoke-Pester -Path "Modules/Tests/Modules/Configuration" -Output Detailed
```

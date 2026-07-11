# Helper Module

The Helper module provides **utility functions** used across all other WinuX modules. It's the foundational toolkit for path resolution, user interaction, and common operations. (Logging now lives in its own [Logging](/modules/logging.md) module.)

## [BranchExists](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/BranchExists.ps1)

- **Description:** Checks whether a Git branch exists in the local repository. Queries the repo for a branch with the specified name and returns `$true` if found, `$false` otherwise.
- **Parameters:** -Branch
- **Usage:** `BranchExists -Branch MyRepo`, `if (BranchExists -Branch "feature/my-feature") { ... }`

```powershell
# Guard logic on whether a branch is present locally
if (BranchExists -Branch "feature/my-feature") {
    Write-Host "Branch exists"
}
```

## [Cd-Desktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Cd-Desktop.ps1)

- **Description:** Navigates the shell to the user's Desktop directory. Sets the current location to the Desktop folder resolved from environment variables, equivalent to `cd ~/Desktop`.
- **Usage:** `Cd-Desktop`

## [Collect-BrowserUrls](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Collect-BrowserUrls.ps1)

- **Description:** Recursively collects all URLs from nested browser group hashtables, flattening the hierarchical `BrowserGroups` structure (from `Configuration.psd1`) into a flat URL array. Handles nested hashtables with `Name`/`Url` pairs and tracks the opened subgroup names. Helper function for `Open-Browser`.
- **Parameters:** -Value, -Depth
- **Usage:** `Collect-BrowserUrls -Value $Configuration.BrowserGroups.GroupName`

Walks the supplied group structure (array, hashtable, or string). For arrays it iterates each item: a hashtable with both `Name` and `Url` keys contributes its URL (and its name to the subgroup list at depth 0), while any other hashtable is recursed into, accumulating both URLs and subgroup names. Returns a hashtable with two keys: `Urls` (the flat list of collected URLs) and `Subgroups` (the top-level subgroup names that were opened). Subgroup names are only tracked at the outermost level (`-Depth 0`); the `-Depth` parameter is incremented internally during recursion and is not intended to be set by callers.

| Parameter | Description                                                                                                               |
| --------- | ------------------------------------------------------------------------------------------------------------------------- |
| `-Value`  | The browser group structure (array, hashtable, or string) to process. Mandatory.                                          |
| `-Depth`  | Recursion depth counter (internal use, default `0`). Tracks nesting so subgroup names are only recorded at the top level. |

```powershell
# Flatten a configured browser group into its URLs
$result = Collect-BrowserUrls -Value $Configuration.BrowserGroups.GroupName
Write-Host "Found $($result.Urls.Count) URLs"

# Inspect the top-level subgroups that were opened
$result.Subgroups
```

**See also:** [Open-Browser](../modules/application.md), [Add Browser Group](../configuration/guides/add-browser-group.md)

## [Convert-GlobalVariablesToParameters](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Convert-GlobalVariablesToParameters.ps1)

- **Description:** Analyzes a PowerShell function definition and converts every `$global:Variable` reference into a regular parameter with an inferred default value. This makes the function self-contained and suitable for creating standalone executables.
- **Parameters:** -FunctionDefinition, -GlobalVariables
- **Usage:** `Convert-GlobalVariablesToParameters -FunctionDefinition $definition`, `Convert-GlobalVariablesToParameters -FunctionDefinition $definition -GlobalVariables MachineSpecificPaths`

Uses regex to find all `$global:` references in the supplied definition, then rewrites the `param()` block via the PowerShell AST (creating one after `[CmdletBinding()]` or at the function body start if none exists) and replaces each global reference with its new parameter. Default values are inferred from known patterns: for example, `$global:MachineSpecificPaths.DotnetProjectsSearchPath` becomes a parameter defaulting to `"$env:USERPROFILE\Development"`, while other paths default to `$null`. If no global variables are found (or none match `-GlobalVariables`), the original definition is returned unchanged.

| Parameter             | Description                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `-FunctionDefinition` | Mandatory. The function definition (script block or string) to process.                                                  |
| `-GlobalVariables`    | Optional array of global variable base names to convert. If omitted, all global variables in the function are converted. |

```powershell
# Convert all global variables in a function to parameters
$definition = (Get-Command Determine-DotnetDependencies).Definition
Convert-GlobalVariablesToParameters -FunctionDefinition $definition

# Restrict conversion to specific global variables by base name
Convert-GlobalVariablesToParameters -FunctionDefinition $definition -GlobalVariables MachineSpecificPaths
```

## [Countdown](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Countdown.ps1)

- **Description:** Displays a colored countdown timer from a given number of seconds down to zero, with an optional message shown before it begins. Counts greater than 3 render in dark cyan and 3 or fewer render in red. Typically used to give a brief pause before destructive operations.
- **Parameters:** -Seconds, -Message
- **Usage:** `Countdown -Seconds 5`, `Countdown -Seconds 5 -Message "Restarting in:"`

## [Create-CenteredBorder](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Create-CenteredBorder.ps1)

- **Description:** Generates a decorative border line centered to the console width, with an optional title wrapped in brackets. Useful for section headers in CLI output. Falls back to a width of 120 characters when the console width is unavailable.
- **Parameters:** -Title, -BorderChar
- **Usage:** `Create-CenteredBorder`, `Create-CenteredBorder -Title "Main Menu"`, `Create-CenteredBorder -Title "Main Menu" -BorderChar "="`

| Parameter     | Description                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------- |
| `-Title`      | Optional text to center in the border (wrapped in brackets). Omit for a plain full-width line. |
| `-BorderChar` | Character used to draw the border (default: `=`).                                              |

```powershell
# Plain full-width border line
Create-CenteredBorder

# Centered title with the default '=' border
Create-CenteredBorder -Title "Main Menu"
# Output: ===================== [Main Menu] =====================

# Centered title with a custom border character
Create-CenteredBorder -Title "Main Menu" -BorderChar "-"
```

## [Create-Executable](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Create-Executable.ps1)

- **Description:** Creates a standalone executable from a PowerShell function and its dependencies. It analyzes the named function, discovers all its custom dependencies, bundles them together, converts global variables to parameters, and produces a self-contained `.exe` via the `ps2exe` module. The result includes all custom function dependencies so the user only needs to run the `.exe`.
- **Parameters:** -FunctionName, -OutputPath, -NoConsole, -RequireAdmin, -IconFile, -Title, -Description, -Company, -Version
- **Usage:** `Create-Executable -FunctionName MyFunction`, `Create-Executable -FunctionName MyFunction -OutputPath C:\Tools\MyFunction.exe -Title "My Tool"`, `Create-Executable -FunctionName MyFunction -RequireAdmin -NoConsole`

Requires the `ps2exe` module (install with `Install-PowerShellModules` or `Install-Module ps2exe -Scope CurrentUser`). The target function must be loaded in the current session. Dependencies are resolved recursively via `Get-PowerShellFunctionDependencies`, and global variable references in both the main function and its dependencies are rewritten into parameters by `Convert-GlobalVariablesToParameters`. External module dependencies are reported but not bundled, so the target machine must have those modules installed. If `-OutputPath` is omitted, the `.exe` is written to the current directory as `FunctionName.exe`; a missing `.exe` extension is appended automatically.

| Parameter       | Description                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------- |
| `-FunctionName` | Name of the PowerShell function to convert to an executable. Mandatory.                       |
| `-OutputPath`   | Optional output path for the `.exe`. Defaults to `FunctionName.exe` in the current directory. |
| `-NoConsole`    | Builds a Windows Forms application with no console window.                                    |
| `-RequireAdmin` | Requires the executable to run with administrator privileges.                                 |
| `-IconFile`     | Path to a custom `.ico` file for the executable.                                              |
| `-Title`        | Title shown in the executable's file properties (defaults to `FunctionName`).                 |
| `-Description`  | Description shown in the executable's file properties.                                        |
| `-Company`      | Company name in the executable metadata (defaults to `WinuX`).                                |
| `-Version`      | Version number in the metadata (defaults to `1.0.0.0`).                                       |

```powershell
# Bundle a function and its dependencies into FunctionName.exe in the current directory
Create-Executable -FunctionName "Determine-DotnetDependencies"

# Custom output path and metadata
Create-Executable -FunctionName "List-Functions" -OutputPath "C:\Tools\ListFunctions.exe" -Title "Function Lister"

# GUI executable that requires administrator privileges
Create-Executable -FunctionName "Configure-System" -RequireAdmin -NoConsole
```

## [Custom-ReadHost](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Custom-ReadHost.ps1)

- **Description:** Wrapper around `Read-Host` that prompts the user for input with customizable colors and formatting. Supports a colored prompt message, an optional leading newline, and secure string input for passwords. Used throughout the modules for consistent, styled user interaction.
- **Parameters:** -PromptMessage, -ForegroundColor, -AddNewLine, -AsSecureString
- **Usage:** `Custom-ReadHost -PromptMessage "Enter value: "`, `Custom-ReadHost -PromptMessage "Enter value: " -ForegroundColor Yellow`, `Custom-ReadHost -PromptMessage "Enter password: " -AsSecureString`

Writes the prompt with `Write-Host -NoNewLine` in the chosen foreground color (prefixing a newline when `-AddNewLine` is set) and then defers to `Read-Host` for the actual input, returning a plain string or, with `-AsSecureString`, a `SecureString`.

| Parameter          | Description                                               |
| ------------------ | --------------------------------------------------------- |
| `-PromptMessage`   | The message to display (required).                        |
| `-ForegroundColor` | Console color for the prompt text (default: `White`).     |
| `-AddNewLine`      | Add a newline before the prompt (default: `$true`).       |
| `-AsSecureString`  | Return the input as a `SecureString`, e.g. for passwords. |

```powershell
# Simple colored prompt returning a string
$value = Custom-ReadHost -PromptMessage "Enter value: " -ForegroundColor Yellow

# Secure prompt for a password (returns a SecureString)
$password = Custom-ReadHost -PromptMessage "Enter password: " -AsSecureString
```

## [DotnetBuildAndRun](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/DotnetBuildAndRun.ps1)

- **Description:** Builds and runs a .NET project in sequence. Invokes `dotnet build` followed by `dotnet run` in the current directory, running in the current shell rather than the background.
- **Usage:** `DotnetBuildAndRun`
- **Alias:** dnbr

**See also:** [DotnetRun](helper.md)

## [DotnetPublish](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/DotnetPublish.ps1)

- **Description:** Publishes a .NET project using its saved publish profiles. Locates the solution file, discovers every project that has publish profiles, and guides you through selecting a project and a profile before running `dotnet publish`. The output is written to a timestamped folder on the Desktop.
- **Usage:** `DotnetPublish`
- **Alias:** dnp

Searches upward and downward (up to 5 levels each) for a `*.sln` file via `Find-Item`, then recursively scans for `*.csproj` projects that contain `Properties\PublishProfiles\*.pubxml` profiles. If a single project or profile is found it is auto-selected; otherwise `Resolve-Selection` presents a menu for each choice. The chosen project is published with `dotnet publish -p:PublishProfile=<profile>` into a Desktop folder named `<Project>_<Profile>_<yyyy_MM_dd>`, and on success offers to open the output folder in Explorer.

```powershell
# Run inside a repository containing a .NET solution.
# Prompts for the project (if more than one has profiles),
# then the publish profile, then publishes to the Desktop.
DotnetPublish

# Same, via alias
dnp
```

## [DotnetRun](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/DotnetRun.ps1)

- **Description:** Runs a .NET project in the current directory by invoking `dotnet run`, assuming the project is already built.
- **Usage:** `DotnetRun`
- **Alias:** dnr

## [Find-EfMigrationProjects](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Find-EfMigrationProjects.ps1)

- **Description:** Discovers EF Core migration projects within a solution using two patterns: dedicated migration projects whose name or directory matches `*Migrations*` (e.g. `Domain.PostgreMigrations`), and the legacy layout where a `Domain` project contains a `Migrations` folder. For each candidate it resolves the database type via `Get-DatabaseTypeFromProject`, locates the `*ModelSnapshot.cs` file, and returns descriptor objects (Name, Path, DbType, snapshot, relative path) consumed by the EfCoreMigrationWizard.
- **Parameters:** -SolutionRoot, -CsprojFiles
- **Usage:** `$csproj = Get-ChildItem -Path <DevRoot>\MySolution -Recurse -Filter "*.csproj" -File`, `Find-EfMigrationProjects -SolutionRoot <DevRoot>\MySolution -CsprojFiles $csproj`

Accepts a pre-enumerated list of `.csproj` files so the caller can walk the solution tree once and reuse it across discovery steps. The legacy-folder pattern only adds a project when it is not already covered by a dedicated migrations project (matched by path or snapshot file), keeping results de-duplicated.

| Parameter       | Description                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------ |
| `-SolutionRoot` | Absolute path to the solution root, used to compute relative project paths. (Mandatory)                      |
| `-CsprojFiles`  | Pre-enumerated collection of `*.csproj` `FileInfo` objects from the solution tree; may be empty. (Mandatory) |

```powershell
# Enumerate the solution's project files once, then discover migration projects
$csproj = Get-ChildItem -Path <DevRoot>\MySolution -Recurse -Filter "*.csproj" -File
$projects = Find-EfMigrationProjects -SolutionRoot <DevRoot>\MySolution -CsprojFiles $csproj
```

**See also:** [Find-EfStartupProject](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Find-EfStartupProject.ps1)

## [Find-EfStartupProject](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Find-EfStartupProject.ps1)

- **Description:** Resolves the best EF Core startup project (the one passed to `dotnet ef --startup-project`) for migration commands. Selects from a solution's API/Web/Startup projects using a layered strategy that prefers projects referencing EF Core Design, falling back to the migrations project and finally any API/Web/Startup project. Accepts a pre-enumerated list of .csproj files so the solution tree is walked only once. Used internally by the EF Core migration wizard.
- **Parameters:** -SolutionRoot, -CsprojFiles, -MigrationsProjectPath, -MigrationsProjectFile
- **Usage:** `Find-EfStartupProject -SolutionRoot $root -CsprojFiles $csproj -MigrationsProjectPath "src\MyMigrations" -MigrationsProjectFile $projFile`

Picks the startup project by working through four strategies in order:

1. An `*.Api.*` / `*Api` project that references EF Core Design.
2. Any API/Web/Startup project that references EF Core Design.
3. If none qualify but the migrations project has Design, use the migrations project.
4. Last resort: any API/Web/Startup project, even without Design (emits a warning).

Returns a hashtable with keys `StartupProject` (a `FileInfo` or `$null`) and `StartupProjectPath` (a relative path string or `$null`).

| Parameter                | Description                                                                                        |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| `-SolutionRoot`          | Absolute path to the solution root, used to compute the relative startup path.                     |
| `-CsprojFiles`           | Pre-enumerated collection of `*.csproj` `FileInfo` objects from the solution tree (may be empty).  |
| `-MigrationsProjectPath` | Relative path of the selected migrations project; used as the fallback startup when it has Design. |
| `-MigrationsProjectFile` | Full path to the migrations `.csproj`, checked for the EF Core Design package.                     |

```powershell
# Resolve the startup project for a solution, reusing an already-enumerated .csproj list
$startup = Find-EfStartupProject -SolutionRoot $root -CsprojFiles $csproj `
    -MigrationsProjectPath "src\MyMigrations" -MigrationsProjectFile $projFile

# Hashtable result: $startup.StartupProject (FileInfo) and $startup.StartupProjectPath (relative path)
$startup.StartupProjectPath
```

## [Find-Item](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Find-Item.ps1)

- **Description:** A robust recursive search for files or directories by pattern with bidirectional search capability: it searches both downward (into subdirectories) and upward (through parent directories) until it finds a match. Supports multiple matches with an interactive selection menu and flexible filtering. Returns a custom object with `Name`, `FullName`, `Path`, `BaseName`, `Extension`, and the raw `Item` (or the full `FileInfo`/`DirectoryInfo` object with `-ReturnFullObject`), or `$null` when nothing is found.
- **Parameters:** -Pattern (required), -StartPath, -MaxUpwardDepth, -MaxDownwardDepth, -SearchTarget, -NameFilter, -SelectFirst, -MenuTitle, -PromptMessage, -SearchMessage, -SuccessMessage, -ErrorMessage, -ReturnFullObject
- **Usage:** `Find-Item -Pattern "*.sln"`, `Find-Item -Pattern "*.csproj" -NameFilter "Domain"`, `Find-Item -Pattern "*" -SearchTarget "Directory" -NameFilter "Database" -MaxDownwardDepth 3`

Starting from `-StartPath` (the current directory by default), the search first scans downward up to `-MaxDownwardDepth` levels. If no match is found, it walks up to the parent directory and searches again, repeating until a match is found or `-MaxUpwardDepth` parent levels have been traversed. The first level that yields any matches stops the traversal. When exactly one item matches (or `-SelectFirst` is given) it returns immediately; multiple matches trigger an interactive selection menu via `Resolve-Selection`.

| Parameter           | Description                                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `-Pattern`          | File or directory pattern to search for, e.g. `*.csproj`, `*.sln`, `*Domain*`. Required.                           |
| `-StartPath`        | Starting path for the search. Defaults to the current directory.                                                   |
| `-MaxUpwardDepth`   | Maximum number of parent directories to traverse upward. Default `5`.                                              |
| `-MaxDownwardDepth` | Maximum depth to recurse downward. Default `5`.                                                                    |
| `-SearchTarget`     | What to search for: `File`, `Directory`, or `Both`. Default `File`.                                                |
| `-NameFilter`       | Additional name filter; matches against the item name for directories, or the containing directory name otherwise. |
| `-SelectFirst`      | Automatically selects the first match without prompting.                                                           |
| `-MenuTitle`        | Custom title for the selection menu when multiple items are found.                                                 |
| `-PromptMessage`    | Custom prompt for the selection menu. Default `"Select an item"`.                                                  |
| `-SearchMessage`    | Custom message shown when the search starts.                                                                       |
| `-SuccessMessage`   | Custom format string for the success message. `{0}` = item name, `{1}` = path.                                     |
| `-ErrorMessage`     | Custom message shown when no items are found.                                                                      |
| `-ReturnFullObject` | Returns the full `FileInfo`/`DirectoryInfo` object instead of the custom result object.                            |

```powershell
# Find a solution file, searching down then up from the current directory
Find-Item -Pattern "*.sln"

# Find .csproj files only within directories whose name contains "Domain"
Find-Item -Pattern "*.csproj" -NameFilter "Domain"

# Find directories named like "Database" up to 3 levels deep
Find-Item -Pattern "*" -SearchTarget "Directory" -NameFilter "Database" -MaxDownwardDepth 3

# Auto-select the first match and get back the raw FileInfo object
$proj = Find-Item -Pattern "*.csproj" -SelectFirst -ReturnFullObject
```

## [Get-DatabaseTypeFromProject](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-DatabaseTypeFromProject.ps1)

- **Description:** Detects the database type of a .NET project by analyzing its project name, project file path, and/or EF Core ModelSnapshot content. Returns `PostgreSQL`, `Oracle`, `SqlServer`, or `Unknown` based on pattern matching. Used by the EF Core migration workflow.
- **Parameters:** -projectName, -projectPath, -snapshotContent
- **Usage:** `Get-DatabaseTypeFromProject -projectName "MyProject.PostgreMigrations"`, `Get-DatabaseTypeFromProject -projectName "MyProject" -snapshotContent $snapshot`

Detection runs in priority order: name and path hints are checked first (`Postgre`/`Npgsql`, `Oracle`, `SqlServer`/`MsSql`). When no hint matches and snapshot content is supplied, the ModelSnapshot text is scanned (`Npgsql`/`PostgreSQL`, `Oracle`, `SqlServer`) for a definitive type. If nothing matches, the function returns `Unknown`.

| Parameter          | Description                                                                         |
| ------------------ | ----------------------------------------------------------------------------------- |
| `-projectName`     | Name of the project to analyze; contains database hints like `Postgre` or `Oracle`. |
| `-projectPath`     | Path to the project file, used as a fallback source of database hints.              |
| `-snapshotContent` | EF Core ModelSnapshot file content used for definitive type detection.              |

```powershell
# Detect from the project name hint
$dbType = Get-DatabaseTypeFromProject -projectName "MyProject.Data.Postgres"
Write-Host "Database: $dbType"   # Output: PostgreSQL

# Fall back to scanning the EF Core ModelSnapshot content
$snapshot = Get-Content "C:\Users\<User>\MyProject\Migrations\ApplicationContextModelSnapshot.cs" -Raw
Get-DatabaseTypeFromProject -projectName "MyProject" -snapshotContent $snapshot
```

## [Get-DbContextFromSnapshot](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-DbContextFromSnapshot.ps1)

- **Description:** Extracts the DbContext class name from an EF Core `*ModelSnapshot.cs` file by parsing its `[DbContext(typeof(...))]` attribute, so the value can be passed to `dotnet ef` via `--context`. Fully-qualified names are reduced to the simple class name (which `dotnet ef` resolves more reliably), and `$null` is returned if the file is missing or no attribute is found. Used by the EF Core migration workflow as the first context-detection source.
- **Parameters:** -SnapshotPath
- **Usage:** `Get-DbContextFromSnapshot -SnapshotPath "<DevRoot>\MyProject\Migrations\MyContextModelSnapshot.cs"`

Reads the snapshot file's raw content and matches the `[DbContext(typeof(...))]` attribute emitted by EF Core. When the captured type is namespace-qualified (contains a dot), only the trailing class name is kept. Together with `Get-DbContextsFromProject`, `Get-EfCoreDbContexts`, and `Resolve-EfMigrationDbContext`, this avoids stale or incorrect `--context` values; the single-snapshot fast path lets `Resolve-EfMigrationDbContext` skip the slow `dotnet ef dbcontext list` design-time build entirely.

| Parameter       | Description                                                    |
| --------------- | -------------------------------------------------------------- |
| `-SnapshotPath` | Full path to the `*ModelSnapshot.cs` file to parse. Mandatory. |

```powershell
# Detect the context name from a migrations project's snapshot
Get-DbContextFromSnapshot -SnapshotPath "<DevRoot>\MyProject\Migrations\MyContextModelSnapshot.cs"
# -> "MyContext"  (or $null if the file is missing or no attribute is found)
```

## [Get-DbContextsFromProject](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-DbContextsFromProject.ps1)

- **Description:** Finds DbContext class names in a C# project directory. Scans `.cs` files (excluding `bin`/`obj`) and returns unique class names that inherit from `DbContext`, including fully-qualified variants when a namespace is available.
- **Parameters:** -ProjectPath
- **Usage:** `Get-DbContextsFromProject -ProjectPath "<DevRoot>\MyProject"`

Recurses the given directory for `*.cs` files, skips anything under `bin` or `obj`, and uses regex to detect classes whose base type is `DbContext` (matching qualified base types like `Microsoft.EntityFrameworkCore.DbContext`). For each match it records the bare class name and, when a `namespace` declaration is present in the file, also the `Namespace.ClassName` form. Results are returned sorted and de-duplicated. A non-existent or non-directory path yields an empty array.

| Parameter      | Description                                       |
| -------------- | ------------------------------------------------- |
| `-ProjectPath` | Path to the project directory to scan. Mandatory. |

```powershell
# Scan a project's source tree for DbContext-derived classes
Get-DbContextsFromProject -ProjectPath "<DevRoot>\MyProject"
```

**See also:** [Helper module](../modules/helper.md)

## [Get-DotnetVersionFromTFM](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-DotnetVersionFromTFM.ps1)

- **Description:** Parses a .NET Target Framework Moniker (TFM) such as `net8.0`, `netcoreapp3.1`, `net48`, or `netstandard2.0` and extracts version information. Returns a `PSCustomObject` with `Major`, `Minor`, `Version`, `IsModern`, and `IsFramework` properties, distinguishing modern .NET / .NET Core from legacy .NET Framework and .NET Standard. Returns `$null` for unrecognized TFM strings.
- **Parameters:** -TFM (required)
- **Usage:** `Get-DotnetVersionFromTFM -TFM "net8.0"`, `Get-DotnetVersionFromTFM -TFM "netcoreapp3.1"`, `Get-DotnetVersionFromTFM -TFM "net48"`

The TFM string is matched against a set of patterns. `net<major>.<minor>` (e.g. `net8.0`) and `netcoreapp<major>.<minor>` (e.g. `netcoreapp3.1`) are treated as modern .NET: the parsed major/minor are returned with `IsModern = $true`. A legacy `net<digit><digits>` moniker (e.g. `net48`) yields `Version = "Framework"` with `IsFramework = $true`. A `netstandard*` moniker yields `Version = "Standard"`. Anything else returns `$null`.

| Parameter | Description                                                                                                          |
| --------- | -------------------------------------------------------------------------------------------------------------------- |
| `-TFM`    | The target framework moniker string to parse (e.g. `net8.0`, `netcoreapp3.1`, `net48`, `netstandard2.0`). Mandatory. |

```powershell
# Parse a modern .NET TFM and read back the version flags
$info = Get-DotnetVersionFromTFM -TFM "net8.0"
Write-Host "Version: $($info.Version), IsModern: $($info.IsModern)"

# Legacy .NET Framework moniker -> Version "Framework", IsFramework $true
Get-DotnetVersionFromTFM -TFM "net48"
```

## [Get-EfCoreDbContexts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-EfCoreDbContexts.ps1)

- **Description:** Runs `dotnet ef dbcontext list` for the provided migration/startup project pair and parses the output into unique, design-time discoverable DbContext names. Returns an empty array when discovery fails.
- **Parameters:** -ProjectPath, -StartupProjectPath, -WorkingDirectory
- **Usage:** `Get-EfCoreDbContexts -ProjectPath "src\MyProject.Migrations" -StartupProjectPath "src\Api" -WorkingDirectory "<DevRoot>\MySolution"`

One of the EF Core context discovery helpers used by `EfCoreMigrationWizard`. It changes to `WorkingDirectory` (typically the solution root), invokes `dotnet ef dbcontext list` against the project/startup pair, and filters the raw `dotnet ef` output (build messages, timestamps, status lines) down to bare context names, returning them sorted and de-duplicated. If the working directory does not exist or the command fails, it returns an empty array rather than throwing.

| Parameter             | Description                                                     |
| --------------------- | --------------------------------------------------------------- |
| `-ProjectPath`        | Migration project path passed to `--project`.                   |
| `-StartupProjectPath` | Startup project path passed to `--startup-project`.             |
| `-WorkingDirectory`   | Directory where `dotnet ef` runs (typically the solution root). |

```powershell
# List design-time discoverable DbContexts for a migration/startup pair
Get-EfCoreDbContexts -ProjectPath "src\MyProject.Migrations" `
                     -StartupProjectPath "src\Api" `
                     -WorkingDirectory "<DevRoot>\MySolution"
```

**See also:** [Resolve-EfMigrationDbContext](#resolve-efmigrationdbcontext)

## [Get-EfCurrentDatabaseType](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-EfCurrentDatabaseType.ps1)

- **Description:** Detects the active database provider from a solution's appsettings. Locates the API/Web/Startup appsettings file (preferring `appsettings.Development.json`, then `appsettings.json`) and reads the `DatabaseConfiguration` section to determine which provider is enabled, returning `"PostgreSQL"`, `"Oracle"`, `"SqlServer"`, or `$null` when it cannot be determined. Used by EfCoreMigrationWizard.
- **Parameters:** -SolutionRoot
- **Usage:** `Get-EfCurrentDatabaseType -SolutionRoot "C:\src\MySolution"`

Recursively scans `SolutionRoot` for `appsettings*.json` files whose containing directory matches `Api`, `Web`, or `Startup`, then picks the highest-priority match. It parses that file's `DatabaseConfiguration` section and returns the provider whose flag is `$true` (`UseNpgSql` -> PostgreSQL, `UseOracle` -> Oracle, `UseSqlServer` -> SqlServer). If no settings file is found, the file cannot be parsed, or no flag is set, it returns `$null`.

| Parameter       | Description                                                                     |
| --------------- | ------------------------------------------------------------------------------- |
| `-SolutionRoot` | Absolute path to the solution root to search for appsettings files. (Mandatory) |

```powershell
# Detect the configured provider for a solution
$active = Get-EfCurrentDatabaseType -SolutionRoot "C:\src\MySolution"

# Branch on the result ($null when undetermined)
if ($active -eq "PostgreSQL") { "Using Npgsql" }
```

**See also:** [EfCoreMigrationWizard](workflow.md#efcoremigrationwizard)

## [Get-EfMigrations](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-EfMigrations.ps1)

- **Description:** Lists the EF Core migration `.cs` files in a migrations folder, sorted by name (which, because the files are timestamp-prefixed, is chronological order). Excludes the generated `*.Designer.cs` and `*Snapshot.cs` files, and returns an empty array when the folder is missing or contains no migrations. Used by the EF Core migration wizard.
- **Parameters:** -MigrationFolderPath
- **Usage:** `Get-EfMigrations -MigrationFolderPath "<DevRoot>\MyProject\Domain.PostgreMigrations\Migrations"`

Returns an array of `FileInfo` objects for the migration files so callers can index into it (for example, taking `[-1]` to get the most recent migration). Because the result is wrapped in `@()`, an empty folder yields a 0-length array rather than `$null`, making the output safe to enumerate or index-check directly.

| Parameter              | Description                                                                                                                      |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `-MigrationFolderPath` | Full path to the folder that holds the migration files. Accepts an empty string; a missing or empty path returns an empty array. |

```powershell
# List migrations chronologically and grab the most recent one
$migrations = Get-EfMigrations -MigrationFolderPath "<DevRoot>\MyProject\Domain.PostgreMigrations\Migrations"
$last = $migrations[-1]
```

## [Get-FilteredParams](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-FilteredParams.ps1)

- **Description:** Filters a parameter hashtable to include only the parameters accepted by a target command. Extracts the valid parameter names from the target command and returns the matching subset, enabling safe parameter forwarding (e.g., splatting). Returns the original hashtable unchanged if the target command cannot be found.
- **Parameters:** -CommandName, -Params
- **Usage:** `Get-FilteredParams -CommandName "Get-Item" -Params @{ Name = "file.txt"; Size = 100; Invalid = "xyz" }`

| Parameter      | Description                                                   |
| -------------- | ------------------------------------------------------------- |
| `-CommandName` | Name of the target command whose parameters to match against. |
| `-Params`      | Hashtable of parameters to filter.                            |

```powershell
# Build a parameter set that may contain keys the target command doesn't accept
$all_params = @{ Name = "file.txt"; Size = 100; Invalid = "xyz" }

# Keep only the keys Get-Item actually accepts -> @{ Name = "file.txt" }
$filtered = Get-FilteredParams -CommandName "Get-Item" -Params $all_params

# Safely splat the filtered set into the target command
Get-Item @filtered
```

## [Get-PowerShellFunctionDependencies](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-PowerShellFunctionDependencies.ps1)

- **Description:** Analyzes a PowerShell function to discover its dependencies using the AST (Abstract Syntax Tree). Parses the function's script block to identify every command it calls and categorizes them into BuiltIn (PowerShell cmdlets), Module (external modules), Custom (functions from the WinuX modules), and Unknown (unresolved commands), and also collects any `global:` variable references. With `-Recursive` it walks the custom dependencies of those custom functions as well.
- **Parameters:** -FunctionName, -Recursive
- **Usage:** `Get-PowerShellFunctionDependencies -FunctionName "MyFunction"`, `Get-PowerShellFunctionDependencies -FunctionName "MyFunction" -Recursive`

Resolves each discovered command with `Get-Command` and buckets it by source: empty source means a built-in cmdlet, a source matching one of the repository's custom modules (Application, Bootstrap, Git, Helper, System, Workflow) is treated as a Custom dependency, anything else is an external Module dependency, and commands that fail to resolve land in Unknown. Returns a hashtable with `BuiltIn`, `Module`, `Custom`, `Unknown`, and `GlobalVariables` keys. Already-processed functions are tracked to prevent infinite recursion loops.

| Parameter       | Description                                                                   |
| --------------- | ----------------------------------------------------------------------------- |
| `-FunctionName` | The name of the function to analyze (mandatory).                              |
| `-Recursive`    | Recursively analyzes the dependencies of any custom functions that are found. |

```powershell
# Analyze a single function's direct dependencies
Get-PowerShellFunctionDependencies -FunctionName "MyFunction"

# Analyze a function and all of its custom dependencies recursively
Get-PowerShellFunctionDependencies -FunctionName "MyFunction" -Recursive
```

## [Get-RepositoryName](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-RepositoryName.ps1)

- **Description:** Extracts the repository name from a Git URL. Parses HTTPS, SSH, and SCP-style Git URLs, stripping any `.git` suffix to return just the repo name. A helper used by `Initialize-Repository`; returns an empty string (with a red error message) on empty input or an unsupported URL format.
- **Parameters:** -RepositoryUrl
- **Usage:** `Get-RepositoryName -RepositoryUrl "https://github.com/user/MyRepo.git"`, `Get-RepositoryName -RepositoryUrl "git@github.com:user/MyRepo.git"`

| Parameter        | Description                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| `-RepositoryUrl` | The Git repository URL to parse (e.g. `https://github.com/user/MyRepo.git` or `git@github.com:user/MyRepo.git`). |

```powershell
# HTTPS URL -> MyRepo
$name = Get-RepositoryName -RepositoryUrl "https://github.com/user/MyRepo.git"
Write-Host "Repo: $name"  # Output: MyRepo

# SCP-style / SSH URL -> MyRepo
Get-RepositoryName -RepositoryUrl "git@github.com:user/MyRepo.git"
```

## [Get-RepositoryPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-RepositoryPath.ps1)

- **Description:** Resolves the repository's key directories without hardcoding folder depth. Walks upward from a starting directory until it finds the folder that holds `Configuration.psd1` (always `...\Windows\PowerShell`), then returns the `PowerShell` root, the `Modules` root, and the `Repo` root derived from that landmark. Because the search is anchored on a real file rather than a count of parent folders, call sites keep working even when moved to a different depth. Replaces the fragile `Split-Path`/`..\..\..` chains formerly duplicated across the profile, `Initialize-Configuration`, and every test file.
- **Parameters:** -StartPath
- **Usage:** `(Get-RepositoryPath).Modules`, `Get-RepositoryPath -StartPath $PSScriptRoot`

| Parameter    | Description                                                                                                                                                                                                                         |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-StartPath` | Directory to begin the upward search from. Defaults to this function's own location, which resolves the repository the Helper module was loaded from. Pass the caller's `$PSScriptRoot` to anchor the search on the caller instead. |

Returns a `[pscustomobject]` with three properties: `PowerShell` (the folder containing `Configuration.psd1`), `Modules` (`<PowerShell>\Modules`), and `Repo` (two levels above `PowerShell`). Throws if no `Configuration.psd1` is found in any parent of `-StartPath`.

```powershell
# From anywhere inside the repo - resolve the custom module root
$modules = (Get-RepositoryPath).Modules

# Anchor the search on the CALLER (e.g. a function that may run from a sandbox)
$paths = Get-RepositoryPath -StartPath $PSScriptRoot
$config = Join-Path -Path $paths.PowerShell -ChildPath "Configuration.psd1"
```

## [Get-RpcRetryPolicy](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-RpcRetryPolicy.ps1)

- **Description:** Centralizes the RPC safety pattern used by VirtualDesktop-heavy workflows. Returns a hashtable of shared retry defaults (`MaxAttempts`, `InitialDelayMs`) and runs an RPC preflight via `Test-RpcServerHealth` (service-status by default, or a live endpoint probe with `-Probe`), triggering `Repair-RpcServer` when unhealthy before callers continue. Used by functions such as Remove-VirtualDesktops, Move-Windows, Set-WorkspaceWindowLayout, and Initialize-WorkspaceWindowLayoutRerun to avoid duplicated preflight/recovery boilerplate.
- **Parameters:** -OperationLabel (default: "operation"), -MaxAttempts (default: 3), -InitialDelayMs (default: 200), -Probe
- **Usage:** `$rpcPolicy = Get-RpcRetryPolicy -OperationLabel "desktop cleanup"`, `Get-RpcRetryPolicy -Probe`

Always returns a hashtable with `MaxAttempts` and `InitialDelayMs` (each floored to a minimum of 1), so callers can feed consistent retry settings into `Invoke-WithRetry`. The preflight and recovery steps are best-effort: they run only when `Test-RpcServerHealth` and `Repair-RpcServer` are available, so the policy is still returned even if those helpers are missing.

| Parameter         | Description                                                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `-OperationLabel` | Human-readable operation label shown in preflight output. Default `"operation"`.                                                 |
| `-MaxAttempts`    | Maximum retry attempts callers should use for `Invoke-WithRetry`. Default `3`.                                                   |
| `-InitialDelayMs` | Initial retry delay in milliseconds for `Invoke-WithRetry`. Default `200`.                                                       |
| `-Probe`          | Preflight uses `Test-RpcServerHealth -Probe` to verify live RPC endpoint responsiveness instead of only checking service status. |

```powershell
# Get shared retry defaults and run a status-based RPC preflight
$rpcPolicy = Get-RpcRetryPolicy -OperationLabel "desktop cleanup"
$rpcMaxAttempts = $rpcPolicy.MaxAttempts
$rpcInitialDelayMs = $rpcPolicy.InitialDelayMs

# Use a live endpoint probe instead of only checking service status
$rpcPolicy = Get-RpcRetryPolicy -Probe
```

## [Get-TargetTerminalWindow](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-TargetTerminalWindow.ps1)

- **Description:** Locates a specific Windows Terminal window from an optional `IntPtr` handle, or returns the first available Windows Terminal window when no handle is given (or no window matches the supplied handle).
- **Parameters:** -TerminalWindowHandle
- **Usage:** `Get-TargetTerminalWindow`, `Get-TargetTerminalWindow -TerminalWindowHandle $handle`

Enumerates `WindowsTerminal` process windows via `Get-WindowHandle`. If `-TerminalWindowHandle` is provided and a window with that handle exists, that window object is returned; otherwise the function falls back to the first Windows Terminal window found. Used internally by `Close-ProjectTerminals` to resolve which terminal to act on.

| Parameter               | Description                                                                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `-TerminalWindowHandle` | Optional `System.IntPtr` handle of the target window. Defaults to `IntPtr.Zero`, which returns the first available Windows Terminal window. |

```powershell
# Get the first available Windows Terminal window
$termWin = Get-TargetTerminalWindow
Write-Host "Terminal handle: $($termWin.Handle)"

# Resolve a specific window by its handle
$termWin = Get-TargetTerminalWindow -TerminalWindowHandle $handle
```

## [Get-WindowTitleCandidates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Get-WindowTitleCandidates.ps1)

- **Description:** Generates window title matching candidates from file names and paths. For each input it produces a de-duplicated set of variations (the original value, the file name, and the file name without extension) for robust window matching.
- **Parameters:** -Names
- **Usage:** `Get-WindowTitleCandidates -Names "<DevRoot>\MyProject\MySolution.sln", "MyRepo"`

For each entry in `-Names` the function emits up to three title fragments: the trimmed original value, the file name (via `Path.GetFileName`), and the file name without extension (via `Path.GetFileNameWithoutExtension`). Blank entries are skipped and duplicates are collapsed, so the result is an ordered, de-duplicated list suitable for matching against open window titles. It is a building block used by `Close-Project` (alongside `Test-WindowTitleCandidates`) to expand a project's names and resolved paths into matchable folder and solution title aliases.

| Parameter | Description                                               |
| --------- | --------------------------------------------------------- |
| `-Names`  | Array of file paths or names to generate candidates from. |

```powershell
# Expand a solution path and a repo name into matchable title fragments
$candidates = Get-WindowTitleCandidates -Names "<DevRoot>\MyProject\MySolution.sln", "MyRepo"
# Returns: "<DevRoot>\MyProject\MySolution.sln", "MySolution.sln", "MySolution", "MyRepo"
```

**See also:** [Close-Project](workflow.md#close-project)

## [Initialize-Directory](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Initialize-Directory.ps1)

- **Description:** Creates a directory if it doesn't already exist. Checks whether the path exists and, if missing, creates it along with all parent directories, printing a green success message. Serves as a helper for the Initialize-Repository function.
- **Parameters:** -Path
- **Usage:** `Initialize-Directory -Path "C:\Temp\MyApp\Data"`

| Parameter | Description                                                                                                  |
| --------- | ------------------------------------------------------------------------------------------------------------ |
| `-Path`   | Directory path to create or verify. Created with all parent directories (`-Force`) if it does not yet exist. |

```powershell
# Create a directory (and any missing parents) only if it is not already present
Initialize-Directory -Path "C:\Temp\MyApp\Data"
```

## [Invoke-GoogleTranslate](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Invoke-GoogleTranslate.ps1)

- **Description:** Translates text between languages using the Google Translate API. The source language is auto-detected unless `-InputLanguage` is provided, and the target language defaults to `Configuration.psd1` → `DefaultTranslateLanguages.OutputLanguage`. Supports both positional (quick) and named parameter usage.
- **Parameters:** -InputLanguage, -OutputLanguage, -Text
- **Usage:** `Invoke-GoogleTranslate kako si`, `Invoke-GoogleTranslate -InputLanguage English -OutputLanguage Croatian -Text hello world`, `Invoke-GoogleTranslate -InputLanguage German -OutputLanguage English -Text guten morgen`
- **Alias:** `translate`

Multi-word input does not need to be quoted: the trailing words are collected and joined automatically. Language names are mapped to Google Translate codes from a built-in table (Afrikaans through Welsh); an unsupported input or output language name produces an error listing the supported languages. The translated result is printed in green as `[OutputLanguage] => <translation>`.

| Parameter         | Description                                                                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-InputLanguage`  | Optional source language override (full language name, e.g. `English`). When omitted (or set to `Auto`/`Detect`/`Automatic`), Google Translate auto-detects the input language. |
| `-OutputLanguage` | Target language for translation. Defaults to `DefaultTranslateLanguages.OutputLanguage` in `Configuration.psd1`.                                                                |
| `-Text`           | The text to translate. Accepts the remaining positional arguments, so multi-word input does not need to be quoted.                                                              |

```powershell
# Quick translation: auto-detect the input language, translate to the configured default output language
Invoke-GoogleTranslate kako si

# Explicit language pair with the translate alias
translate -InputLanguage English -OutputLanguage Croatian -Text hello world

# Translate German to English
Invoke-GoogleTranslate -InputLanguage German -OutputLanguage English -Text guten morgen
```

**See also:** [Configuration Reference](../configuration/configuration-reference.md)

## [Invoke-PrivacyRequest](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Invoke-PrivacyRequest.ps1)

- **Description:** Helper that makes an HTTP request either directly via `Invoke-RestMethod` or, when `-UseTor` is specified, through the Tor SOCKS5 proxy via `Invoke-TorRequest`. Used by `Test-PrivacyStatus` to perform privacy verification checks in both VPN and Tor modes.
- **Parameters:** -Uri, -UseTor, -TimeoutSec, -RetryCount
- **Usage:** `Invoke-PrivacyRequest -Uri "https://api.ipify.org?format=json"`, `Invoke-PrivacyRequest -Uri "https://check.torproject.org/api/ip" -UseTor`

| Parameter     | Description                                                                   |
| ------------- | ----------------------------------------------------------------------------- |
| `-Uri`        | The URI to request. Mandatory.                                                |
| `-UseTor`     | Switch. Routes the request through the Tor proxy instead of a direct request. |
| `-TimeoutSec` | Request timeout in seconds. Default `3`.                                      |
| `-RetryCount` | Number of retry attempts for Tor requests. Default `1`.                       |

```powershell
# Direct (VPN) request returning the current public IP
Invoke-PrivacyRequest -Uri "https://api.ipify.org?format=json"

# Same check routed through the Tor proxy, with a longer timeout and extra retries
Invoke-PrivacyRequest -Uri "https://check.torproject.org/api/ip" -UseTor -TimeoutSec 5 -RetryCount 2
```

**See also:** [Invoke-TorRequest](helper.md), [Test-PrivacyStatus](helper.md)

## [Invoke-TorRequest](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Invoke-TorRequest.ps1)

- **Description:** Makes an HTTP request through Tor for anonymity. Routes `Invoke-RestMethod` through the Tor SOCKS5 proxy with automatic port discovery (9150 for Tor Browser, 9050 for the Tor service) and built-in retry logic for connection failures. Used by privacy-focused queries such as `Test-PrivacyStatus` to verify Tor connectivity.
- **Parameters:** -Uri, -TimeoutSec, -RetryCount
- **Usage:** `Invoke-TorRequest -Uri "https://check.torproject.org/api/ip"`, `Invoke-TorRequest -Uri "https://api.example.com/data" -TimeoutSec 30 -RetryCount 3`

Tries each Tor SOCKS5 port (`socks5://127.0.0.1:9150` then `9050`) in turn, attempting the request up to `-RetryCount` times per port. Connection-refused / proxy-unavailable errors short-circuit to the next port, while other transient network errors are retried with a brief pause. Returns the deserialized response object on success, or `$null` if no port responds.

| Parameter     | Description                               |
| ------------- | ----------------------------------------- |
| `-Uri`        | HTTP(S) URL to fetch (required).          |
| `-TimeoutSec` | Request timeout in seconds (default: 15). |
| `-RetryCount` | Number of retries per port (default: 2).  |

```powershell
# Check Tor exit-node IP via the Tor Project check API
$response = Invoke-TorRequest -Uri "https://check.torproject.org/api/ip"
Write-Host "Response: $($response.IsTor)"

# Fetch JSON through Tor with a longer timeout and more retries
$data = Invoke-TorRequest -Uri "https://api.example.com/data" -TimeoutSec 30 -RetryCount 3
```

## [Invoke-WithOptionalRetry](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Invoke-WithOptionalRetry.ps1)

- **Description:** Executes a script block with optional retry/backoff behavior. When `-EnableRetry` is set and `Invoke-WithRetry` is available it runs the operation with exponential backoff; otherwise it executes the script block directly. Centralizes the repeated "retry if available, otherwise run directly" branch used by RPC/COM-sensitive VirtualDesktop operations, and can pass an `-OnRetry` recovery hook through to `Invoke-WithRetry`.
- **Parameters:** -ScriptBlock, -MaxAttempts (default: 3), -InitialDelayMs (default: 200), -EnableRetry, -OnRetry
- **Usage:** `Invoke-WithOptionalRetry -ScriptBlock { Get-DesktopList }`, `Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -MaxAttempts 3 -InitialDelayMs 200`, `Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -OnRetry { param($ErrorRecord, $Attempt) Reset-VirtualDesktopState }`

Avoids duplicating if/else branches in callers that need to run the same operation either with retries (RPC/COM transient failure handling) or without. When retry mode is enabled and the helper is present, the call is delegated to `Invoke-WithRetry`; when `-OnRetry` is supplied, that hook is forwarded so callers can attach targeted recovery, such as resetting stale VirtualDesktop COM state between attempts.

| Parameter         | Type          | Default | Description                                                                                                                                            |
| ----------------- | ------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-ScriptBlock`    | `scriptblock` | -       | The operation to execute (mandatory).                                                                                                                  |
| `-MaxAttempts`    | `int`         | `3`     | Maximum retry attempts when retry mode is enabled.                                                                                                     |
| `-InitialDelayMs` | `int`         | `200`   | Initial retry delay in milliseconds.                                                                                                                   |
| `-EnableRetry`    | `switch`      | -       | When specified, attempts to use `Invoke-WithRetry` if available.                                                                                       |
| `-OnRetry`        | `scriptblock` | -       | Optional hook passed through to `Invoke-WithRetry`; receives the ErrorRecord and failed attempt number after each failed attempt that will be retried. |

```powershell
# Run directly, no retries
Invoke-WithOptionalRetry -ScriptBlock { Get-DesktopList }

# Run with exponential backoff (3 attempts, 200 ms initial delay)
Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -MaxAttempts 3 -InitialDelayMs 200

# Retry with a recovery hook between failed attempts
Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -OnRetry {
    param($ErrorRecord, [int]$Attempt)
    Reset-VirtualDesktopState
}
```

**See also:** [Invoke-WithRetry](helper.md#invoke-withretry)

## [Invoke-WithRetry](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Invoke-WithRetry.ps1)

- **Description:** Executes a script block with exponential backoff retry logic, attempting it up to `-MaxAttempts` times. Useful for transient failures such as network errors, COM initialization failures, RPC timeouts, or temporary resource contention. When `-OnRetry` is supplied, the hook runs after a failed attempt and before the next retry delay, receiving the ErrorRecord and the failed attempt number; hook failures are treated as best-effort so the original retry flow is preserved.
- **Parameters:** -ScriptBlock, -MaxAttempts, -InitialDelayMs, -OnRetry
- **Usage:** `Invoke-WithRetry -ScriptBlock { Invoke-RestMethod -Uri $url } -MaxAttempts 5`, `Invoke-WithRetry -ScriptBlock { Get-DesktopList } -OnRetry { param($ErrorRecord, $Attempt) Reset-VirtualDesktopState }`

Attempts the script block up to `-MaxAttempts` times. The delay starts at `-InitialDelayMs` milliseconds and doubles after each failed attempt (exponential backoff). If the final attempt still fails, the original error is rethrown.

| Parameter         | Type          | Default | Description                                                                                                                                            |
| ----------------- | ------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-ScriptBlock`    | `scriptblock` | -       | The code to execute (required).                                                                                                                        |
| `-MaxAttempts`    | `int`         | `3`     | Maximum number of attempts before rethrowing the final failure.                                                                                        |
| `-InitialDelayMs` | `int`         | `100`   | Starting delay in milliseconds; doubles after each failed attempt.                                                                                     |
| `-OnRetry`        | `scriptblock` | -       | Optional recovery hook invoked after a failed attempt and before the next delay; receives the `ErrorRecord` and the failed attempt index. Best-effort. |

```powershell
# Retry a flaky network call with up to 5 attempts
Invoke-WithRetry -ScriptBlock { Invoke-WebRequest "https://api.example.com" } -MaxAttempts 5 -InitialDelayMs 200

# Retry with a recovery hook that resets stale COM state between attempts
Invoke-WithRetry -ScriptBlock { Get-DesktopList } -OnRetry {
    param($ErrorRecord, [int]$Attempt)
    Reset-VirtualDesktopState
}
```

## [List-AvailableColors](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/List-AvailableColors.ps1)

- **Description:** Displays all available PowerShell console colors, showing a palette of every foreground and background color combination. Useful for development and UI design.
- **Usage:** `List-AvailableColors`

## [List-Functions](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/List-Functions.ps1)

- **Description:** Parses the per-module documentation pages under `docs/modules/*.md` (and the fork-owned `docs/custom/*.md` pages, when present) to extract every documented function's name, signature, and description, then lists them grouped by module category with a total count. With `-Category` or `-Function` it filters interactively (resolving by number or name) to a category or specific functions; with `-ListDiscrepancies` it reports mismatches between the documentation and the functions actually loaded in the session.
- **Parameters:** -Category, -Function, -ListDiscrepancies, -Quiet
- **Usage:** `List-Functions`, `List-Functions -Category "System"`, `List-Functions -Function "Open-Browser", "Set-Wallpaper"`, `List-Functions -ListDiscrepancies`, `List-Functions -ListDiscrepancies -Quiet`

Reads the man-style `## [FunctionName](url)` entries from the docs pages (located via `MachineSpecificPaths.Projects.Self.Docs`) and parses each entry's contiguous `- **Key:** value` bullet block into module categories; `docs/custom/` pages merge into their mirror module's category, so fork-only functions are listed and checked alongside engine ones (the Custom area's `README.md` landing page is skipped). The default run prints every category with its functions and a total count. The discrepancy check compares the documented functions against functions actually loaded from the modules under `MachineSpecificPaths.Projects.Self.Modules`, honoring `Configuration.FunctionDiscrepancyExclusions`, and flags any that are documented but not loaded (or loaded but not documented). Output colors come from `Configuration.ListFunctionsColors`. The parameter sets are mutually exclusive, so only one filter may be used at a time.

| Parameter            | Description                                                                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Category`          | One or more module categories to list (e.g. `Application`, `System`); resolved interactively by number or name.                                                            |
| `-Function`          | One or more specific function names to display; resolved interactively by number or name.                                                                                  |
| `-ListDiscrepancies` | Switch. Reports functions documented in the README but not loaded, and functions loaded but not documented.                                                                |
| `-Quiet`             | Switch (with `-ListDiscrepancies`). Suppresses the "no discrepancies" success banner so output appears only when a discrepancy exists - used by the profile startup check. |

```powershell
# List all documented functions, grouped by module
List-Functions

# List only the functions in a given category
List-Functions -Category "System"

# Show detailed entries for specific functions
List-Functions -Function "Open-Browser", "Set-Wallpaper"

# Audit the README against the actually-loaded functions
List-Functions -ListDiscrepancies
```

**See also:** [Show-FunctionDetails](helper.md#show-functiondetails)

## [Loading-Spinner](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Loading-Spinner.ps1)

- **Description:** Displays an animated loading spinner, or runs code while showing spinner feedback. Four modes: run a scriptblock with a spinner (`-Function`), start a continuous spinner (`-Start`), stop it (`-Stop`), and pause/resume an active spinner (`-Pause`/`-Resume`). Supports configurable spinner styles with optional labels.
- **Parameters:** -Function, -Label, -Style, -Start, -Stop, -Spinner, -Completed, -Discard, -Pause, -Resume
- **Styles:** BrailleBlocks, Dots, Line, Arrows, Box, Circle, Moon, Clock, Star, Dot, GrowingDots, BlockFill, Pulse, Binary, Triangle, BarBlocks, SquareCorners, Hamburger, Arc
- **Usage:** `Loading-Spinner -Function { Start-Sleep 3 } -Label "Processing" -Style Dots`, `$spinner = Loading-Spinner -Start -Label "Working"`, `Loading-Spinner -Stop -Spinner $spinner`, `Loading-Spinner -Pause`, `Loading-Spinner -Resume`

Spinner styles are read from `LoadingSpinners` in `Configuration.psd1` (falling back to `DefaultSpinner`); each style defines its symbols and animation delay. The `-Function` (job-based) mode runs the scriptblock in a background job while the main thread animates, then returns the job's output and leaves a green checkmark.

The continuous `-Start` spinner is globally coordinated: there is only ever a SINGLE animation timer and a SINGLE spinner line on screen, no matter how many nested `-Start` calls are made. A nested `-Start` does NOT spawn a second timer; it just relabels the existing spinner, and only the outermost `-Stop` tears the timer down. Rendering uses only carriage returns (no absolute cursor positioning), so the spinner is immune to terminal scrolling and survives redirected output. When surrounding code must print its own output while the spinner is live, wrap it in `-Pause`/`-Resume` so the spinner line is erased first and re-drawn afterwards.

| Parameter    | Description                                                                                                                             |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `-Function`  | Scriptblock to execute while showing the spinner (Function parameter set). Returns the scriptblock's output.                            |
| `-Label`     | Optional text label shown next to the spinner.                                                                                          |
| `-Style`     | Spinner animation style (default `Dots`). Must exist in `Configuration.LoadingSpinners`.                                                |
| `-Start`     | Starts a continuous spinner; returns a handle hashtable to pass to a later `-Stop`.                                                     |
| `-Stop`      | Stops an active spinner.                                                                                                                |
| `-Spinner`   | The handle hashtable returned by `-Start`, passed to `-Stop`.                                                                           |
| `-Completed` | With `-Stop`: forces a green checkmark even when the spinner had no label. Ignored when the spinner has a label or with `-Discard`.     |
| `-Discard`   | With `-Stop`: erases the line with no checkmark (use on error/abort paths). Takes precedence over `-Completed` and the label checkmark. |
| `-Pause`     | Temporarily erases the active spinner line so other output can be written cleanly.                                                      |
| `-Resume`    | Re-draws the spinner after a `-Pause`.                                                                                                  |

```powershell
# Job mode: run code in the background while a spinner animates
Loading-Spinner -Function { Start-Sleep 3 } -Label "Processing" -Style Dots

# Manual mode: start, do work, then stop (leaves a green checkmark for labeled spinners)
$spinner = Loading-Spinner -Start -Label "Downloading" -Style Bar
Start-Sleep 5
Loading-Spinner -Stop -Spinner $spinner

# Pause/Resume to print caller output without overlapping the spinner line
$spinner = Loading-Spinner -Start -Label "Working"
Loading-Spinner -Pause
Write-Host "`nSome status the caller wants to print"
Loading-Spinner -Resume
Loading-Spinner -Stop -Spinner $spinner

# Abort path: stop without showing a success checkmark
Loading-Spinner -Stop -Spinner $spinner -Discard
```

**See also:** [Preview-LoadingSpinners](helper.md)

## [NpmInstallAndStart](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/NpmInstallAndStart.ps1)

- **Description:** Installs npm dependencies and starts a Node.js project by running `npm install` followed by `npm start` in sequence. Useful for quickly spinning up Node.js web app development workflows.
- **Usage:** `NpmInstallAndStart`
- **Alias:** nir

## [Preview-LoadingSpinners](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Preview-LoadingSpinners.ps1)

- **Description:** Displays every loading spinner style defined in `Configuration.LoadingSpinners`, animating them all simultaneously for 10 seconds so you can pick a preferred loading animation.
- **Usage:** `Preview-LoadingSpinners`

Iterates through all spinner styles in `Configuration.LoadingSpinners`, animating each one with its configured frames on its own line. The preview runs for roughly 10 seconds, hides the cursor while animating, and prints `=> Preview complete!` when finished. If no spinner configuration is found in the global configuration, it reports the issue and returns without animating.

Available spinner styles (configured under `LoadingSpinners`):

- `Dots` (default) - ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
- `BrailleBlocks` - ⣾⣿⣽⣿⣻⣿...
- `Line` - |/-\
- `Arrows` - ←↖↑↗→↘↓↙
- `Circle` - ◐◓◑◒
- `Moon` - 🌑🌒🌓🌔🌕...
- And more...

```powershell
# Animate all configured spinner styles for ~10 seconds
Preview-LoadingSpinners
```

## [ProcessGroupRecursive](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/ProcessGroupRecursive.ps1)

- **Description:** Internal helper used by `Resolve-Selection` to recursively flatten and navigate hierarchical group configurations with unlimited nesting depth. Detects the structure type of each group (Name/Url arrays, nested hashtable arrays, string arrays, or mixed arrays with Name/Url entries alongside nested sub-groups at the same level), generates indexed display items, and builds a lookup map for rapid name to selection resolution. Call it via `Resolve-Selection -GroupsConfig`, not directly.
- **Parameters:** -GroupValue, -IndexPath, -DisplayItems, -LookupMap, -PathNames, -Depth
- **Usage:** `ProcessGroupRecursive -GroupValue $value -IndexPath "1" -DisplayItems $items -LookupMap $map -PathNames $names`

This is an internal recursion primitive for menu rendering. For each group it inspects the contained elements to classify the structure (`StringArray`, `NameUrlArray`, `NestedHashtables`, `MixedArray`, or `Unknown`), appends a display line carrying its `IndexPath` and nesting `Depth`, and records a lookup entry keyed by both the dot-notation index path (e.g. `1.2.3`) and the friendly name. It then recurses into nested hashtables to expand child groups, while Name/Url leaf entries are registered directly. `DisplayItems`, `LookupMap`, and `PathNames` are accumulated by reference across the recursion.

| Parameter       | Description                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------ |
| `-GroupValue`   | The current group to process (hashtable, array, or string).                                      |
| `-IndexPath`    | The dot-notation path (e.g. `1.2.3`) representing the item's position in the hierarchy.          |
| `-DisplayItems` | Array list accumulating menu display lines. Passed by reference and modified.                    |
| `-LookupMap`    | Hashtable mapping friendly names to selection objects. Passed by reference and modified.         |
| `-PathNames`    | Array list of names representing the current path in the hierarchy.                              |
| `-Depth`        | Current nesting depth (0 at root). Controls indentation in the display. Optional, defaults to 0. |

**See also:** [Add Browser Group](../configuration/guides/add-browser-group.md)

## [Refresh-BrowserTabs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Refresh-BrowserTabs.ps1)

- **Description:** Hard-refreshes (Ctrl+Shift+R) every tab of every open Firefox, Chrome, Edge, and Brave window exactly once. Reads the real browser tab strip through UI Automation and activates each tab directly via its SelectionItemPattern before sending the refresh, so page-content `role="tab"` widgets no longer inflate the count and no tab is refreshed twice; falls back to a Ctrl+Tab cycle bounded by the accurate tab count, then to refreshing only the active tab, when selection is unavailable. Verifies foreground focus per window first and skips any window it cannot focus, so keystrokes never land on the wrong window. Restores each window's originally-active tab afterwards (falling back to the first tab when it cannot be determined or re-selected). Typically called after `Set-SystemTheme` to apply theme changes instantly without a manual refresh.
- **Usage:** `Refresh-BrowserTabs`

Acquires verified foreground focus for each browser window via `Confirm-WindowForeground` (skipping any window it cannot focus), then enumerates the window's real chrome tabs through UI Automation - excluding `role="tab"` widgets that web pages expose inside their document so the count is not inflated. Each tab is activated through its `SelectionItemPattern` and hard-refreshed with `SendKeys` (`Ctrl+Shift+R`), guaranteeing each tab is hit exactly once without relying on `Ctrl+Tab` keystrokes landing. If no tab is selectable it falls back to a deterministic `Ctrl+Tab` cycle bounded by the accurate tab count, and if UI Automation exposes no tabs at all it refreshes only the active tab. Because refreshing moves the selection, the originally-active tab is recorded beforehand (via each tab's `SelectionItemPattern` `IsSelected` state) and re-selected afterwards - in the cycle fallback it is restored with `Ctrl+1`..`Ctrl+8`; when the original tab is unknown or beyond the eighth, the window is left on its first tab. Supported process names (`firefox`, `chrome`, `msedge`, `brave`) match the browsers configured under `Universal.Browsers` in `Configuration.psd1`.

```powershell
# Refresh tabs in every open browser
Refresh-BrowserTabs

# Verbose diagnostic output
Set-LogLevel Verbose { Refresh-BrowserTabs }
```

**See also:** [Set-SystemTheme](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Set-SystemTheme.ps1)

## [Rerun-LastCommand](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Rerun-LastCommand.ps1)

- **Description:** Reruns a recent command in a fresh, non-admin PowerShell shell. When an operation fails in a way that requires a clean shell environment (e.g., RPC errors, layout verification failures), it reads the PSReadLine history, offers the recent non-rerun commands for selection (or auto-selects the most recent with `-AutoAccept`), opens Windows Terminal in the current directory running the selected command, and closes the original terminal tab. Caller-specific recovery such as workspace layout, FancyZones, desktop, cache, or RPC preparation is handled before invoking this generic rerun helper.
- **Parameters:** -NumberOfLastTriggeringCommands, -ErrorMessage, -AutoAccept
- **Usage:** `Rerun-LastCommand`, `Rerun-LastCommand -AutoAccept`, `Rerun-LastCommand -NumberOfLastTriggeringCommands 10`, `Rerun-LastCommand -ErrorMessage "An error that needs a fresh shell occurred"`

Recovers from failures that require a pristine shell by reading the PSReadLine history file (`HistorySavePath`) and presenting the last N typed commands, filtered to skip blanks, duplicates, and prior `Rerun-LastCommand` invocations. The chosen command is run via `Open-Terminal` in a new Windows Terminal tab, prefixed with a `Set-Location` back to the original working directory. After launching, the original window is refocused and its tab is closed (`Ctrl+Shift+W`), and the current process exits.

| Parameter                         | Description                                                         |
| --------------------------------- | ------------------------------------------------------------------- |
| `-NumberOfLastTriggeringCommands` | Number of recent commands to display for selection. Default is `5`. |
| `-ErrorMessage`                   | Optional custom message shown before the command selection menu.    |
| `-AutoAccept`                     | Skips the menu and automatically selects the most recent command.   |

```powershell
# Interactive selection from the last 5 commands (default error message)
Rerun-LastCommand

# Automatically rerun the most recent command, no prompt
Rerun-LastCommand -AutoAccept

# Show more history and a custom message before selecting
Rerun-LastCommand -NumberOfLastTriggeringCommands 10 -ErrorMessage "Layout verification failed; rerunning in a fresh shell"
```

**See also:** [Resolve-Selection](helper.md#resolve-selection), [Open-Terminal](application.md#open-terminal), [Initialize-WorkspaceWindowLayoutRerun](window.md#initialize-workspacewindowlayoutrerun)

## [Resolve-ConfigPathValue](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Resolve-ConfigPathValue.ps1)

- **Description:** Traverses a dot-notation path string through the nested `MachineSpecificPaths` configuration hashtable (e.g. `Projects.MyProject.Root`) and returns the value at the end of the path. Returns `$null` if the path is empty or any segment along the way cannot be resolved.
- **Parameters:** -PathExpression
- **Usage:** `Resolve-ConfigPathValue -PathExpression "Universal.DefaultBrowser"`, `Resolve-ConfigPathValue -PathExpression "Projects.MyProject.MySolution.Solution"`

## [Resolve-EfMigrationDbContext](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Resolve-EfMigrationDbContext.ps1)

- **Description:** Resolves which DbContext (if any) to pass to `dotnet ef` migration commands and whether an explicit `--context` flag is required. Fast-paths single-context migration projects (exactly one `*ModelSnapshot.cs`) by skipping both the project-wide source scan and the slow `dotnet ef dbcontext list` design-time build; ambiguous or empty projects fall back to full discovery, prompting the user when more than one context is present. Used by `EfCoreMigrationWizard`.
- **Parameters:** -MigrationProject, -StartupProjectDirectory, -MigrationsProjectPath, -StartupProjectPath, -SolutionRoot
- **Usage:** `Resolve-EfMigrationDbContext -MigrationProject $proj -MigrationsProjectPath "src\MyProject.Migrations" -StartupProjectPath "src\MyProject.Api" -SolutionRoot "<DevRoot>\MySolution"`

Determines the DbContext name and the `--context` decision for migration commands. The fast path relies on the fact that a migrations assembly has exactly one `*ModelSnapshot.cs` per DbContext: a single snapshot means a single context, which `dotnet ef` can resolve without `--context`, so the function returns immediately and avoids a multi-second design-time build. When zero or multiple snapshots make the context ambiguous, it scans the migration and startup project sources for `DbContext` classes and uses `dotnet ef dbcontext list` as the authority, prompting for selection if several contexts exist. Returns a hashtable with keys `ContextName` (string or `$null`) and `UseExplicitContext` (bool).

| Parameter                  | Description                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `-MigrationProject`        | Selected migration-project descriptor (from `Find-EfMigrationProjects`); uses its `.Path` and `.SnapshotFile`. Mandatory. |
| `-StartupProjectDirectory` | Full path to the startup project directory, used for source-scan disambiguation. Optional.                                |
| `-MigrationsProjectPath`   | Relative migrations project path passed to `dotnet ef` (`--project`). Mandatory.                                          |
| `-StartupProjectPath`      | Relative startup project path passed to `dotnet ef` (`--startup-project`). Optional.                                      |
| `-SolutionRoot`            | Working directory for the `dotnet ef` invocation (solution root). Mandatory.                                              |

```powershell
# Resolve the DbContext for a migration project, with startup project for disambiguation
$ctx = Resolve-EfMigrationDbContext -MigrationProject $proj -StartupProjectDirectory $dir `
    -MigrationsProjectPath "src\MyProject.Migrations" -StartupProjectPath "src\MyProject.Api" `
    -SolutionRoot "<DevRoot>\MySolution"

# $ctx.ContextName        -> e.g. "MyContext" (or $null if none resolved)
# $ctx.UseExplicitContext -> $true when --context must be passed explicitly
```

## [Resolve-ProjectPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Resolve-ProjectPath.ps1)

- **Description:** Resolves a project's file paths from the configuration mappings. Looks the project up in `Configuration.ProjectTerminals` (or `Configuration.RepositoryGroups` with `-ForRepository`) and walks the dot-notation reference through `MachineSpecificPaths` to produce the actual path(s). Can return a single named path or the full collection of paths for a project.
- **Parameters:** -ProjectName, -PathKey, -ForRepository
- **Usage:** `Resolve-ProjectPath -ProjectName MyProject`, `Resolve-ProjectPath -ProjectName MyProject -PathKey "LocalPath"`, `Resolve-ProjectPath -ProjectName MyRepo -ForRepository`

In project mode (the default), the function finds the matching entry in `Configuration.ProjectTerminals`, resolves its `BasePath` against `MachineSpecificPaths`, then returns either the value of the requested `-PathKey` or every path listed under the project's `Paths`. In repository mode (`-ForRepository`), it instead reads `Configuration.RepositoryGroups`, resolves the `LocalPath` against `MachineSpecificPaths`, builds the remote URL from `Configuration.Universal.GitHub.Base` plus the resolved `UrlPath`, and returns a `PSCustomObject` with `RepositoryUrl` and `LocalPath`. Unknown projects, missing path keys, or unresolvable (null) path segments emit a red error and abort.

| Parameter        | Description                                                                                                                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-ProjectName`   | Project (or repository) key from configuration. Required.                                                                                            |
| `-PathKey`       | Optional specific path key to return (e.g. `LocalPath`, `RemotePath`). Omit to return all paths defined for the project. Ignored in repository mode. |
| `-ForRepository` | Switch. Resolve against `RepositoryGroups` and return a `PSCustomObject` with `RepositoryUrl` and `LocalPath` instead of plain project paths.        |

```powershell
# Resolve a single named path for a project
$path = Resolve-ProjectPath -ProjectName MyProject -PathKey "LocalPath"
Write-Host "Project at: $path"

# Return every path configured for the project
Resolve-ProjectPath -ProjectName MyProject

# Resolve a repository: returns { RepositoryUrl, LocalPath }
$repo = Resolve-ProjectPath -ProjectName MyRepo -ForRepository
```

## [Resolve-Selection](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Resolve-Selection.ps1)

- **Description:** The canonical interactive menu selector used throughout the system. Presents a numbered menu and returns the selected option(s) by number or name. Supports a flat mode (simple Yes/No or custom option list) and a hierarchical mode (when `-GroupsConfig` is provided) that navigates nested groups with dot-notation selection ("Parent.ChildGroup"), automatic expansion of parent groups, and parent/child navigation. Honors a default option via `-DefaultOptionIndex` so pressing Enter with no input selects it.
- **Parameters:** -OptionList, -InputObject, -MenuTitle, -HideMenuTitle, -HideSelection, -PromptMessage, -HidePromptMessage, -AllowEmptyPromptResponse, -AllowMultipleSelections, -DefaultOptionIndex, -GroupsConfig
- **Usage:** `Resolve-Selection`, `Resolve-Selection -OptionList @("Alpha", "Beta", "Gamma")`, `Resolve-Selection -OptionList @("English", "Espanol", "Francais") -PromptMessage "Select a language"`, `Resolve-Selection -OptionList @("Alpha", "Beta", "Gamma") -DefaultOptionIndex 1`, `Resolve-Selection -GroupsConfig $Configuration.BrowserGroups -AllowMultipleSelections`

Used by `Open-Browser`, `Open-Project`, `Set-Locale`, `Set-DisplayLanguage`, `Configure-NerdFont`, and others as the shared selection primitive. In flat mode it accepts a number (1-based) or the literal option text. In hierarchical mode (`-GroupsConfig`), parent groups expand to their direct children automatically, and `-AllowMultipleSelections` permits space/comma-separated picks. Pre-selected values can be passed via `-InputObject` (or the pipeline) to skip the interactive prompt entirely.

| Parameter                   | Type       | Description                                                                                            |
| --------------------------- | ---------- | ------------------------------------------------------------------------------------------------------ |
| `-OptionList`               | `string[]` | Flat list of options to display (default: `@("Yes", "No")`). Ignored when `-GroupsConfig` is provided. |
| `-InputObject`              | `string[]` | Pre-selected option(s), also accepted from the pipeline. Skips the interactive menu when supplied.     |
| `-MenuTitle`                | `string`   | Title shown at the top of the menu (default: `"[Available Options]"`).                                 |
| `-HideMenuTitle`            | `switch`   | Suppresses the menu title.                                                                             |
| `-HideSelection`            | `switch`   | Hides the option list / final selection echo.                                                          |
| `-PromptMessage`            | `string`   | Custom prompt text shown before the menu; a generic prompt is used when omitted.                       |
| `-HidePromptMessage`        | `switch`   | Suppresses the prompt message.                                                                         |
| `-AllowEmptyPromptResponse` | `switch`   | Returns `$null` on empty input instead of re-prompting (when no default is set).                       |
| `-AllowMultipleSelections`  | `switch`   | Accepts space/comma-separated numbers or names to select multiple items.                               |
| `-DefaultOptionIndex`       | `int`      | 1-based index of the option returned when the user presses Enter (`0` = no default).                   |
| `-GroupsConfig`             | `object`   | Hierarchical group definitions (hashtable). Enables nested menu navigation and expansion.              |

```powershell
# Basic flat menu - user must type a selection
Resolve-Selection -OptionList @("Alpha", "Beta", "Gamma")

# With a default - pressing Enter selects "Alpha"
# Prompt shows: Enter selection by number or name (default: Alpha):
Resolve-Selection -OptionList @("Alpha", "Beta", "Gamma") -DefaultOptionIndex 1

# Custom prompt text
Resolve-Selection -OptionList @("English", "Espanol", "Francais") -PromptMessage "Select a language"

# Hierarchical browser-group menu with multi-select support
Resolve-Selection -GroupsConfig $Configuration.BrowserGroups -AllowMultipleSelections
```

## [Run-Project](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Run-Project.ps1)

- **Description:** Opens Windows Terminal tabs for one or more configured runnable projects. Selects from `Configuration.RunnableProjects` (with optional multi-select via `Resolve-Selection`) and runs each project's configured commands in its own tab. Existing terminal tabs for a project are detected and closed first to prevent duplicates, then fresh tabs are opened; a database provider is resolved (prompting when several are configured) and Docker is started when required. Both the project selection and database provider menus default to the first option when Enter is pressed.
- **Implementation Note:** Passes the originating Windows Terminal handle/title into `Close-ProjectTerminals` so Docker cold-start focus changes do not cause duplicate tabs in a different terminal window.
- **Parameters:** -Project, -InSameShell
- **Usage:** `Run-Project`, `Run-Project -Project "MyProject", "OtherProject"`, `Run-Project -Project "MyProject" -InSameShell:$false`
- **Alias:** rp

Reads `Configuration.RunnableProjects` for the menu and `RunnableProjectMappings` for each project's run commands, pairing them against `ProjectTerminals` path keys (e.g. `Api`, `Ui`) so every path key gets a matching command and its own tab titled `<Project>.<PathKey>`. If a project has database providers configured, the matching Docker Compose file is started before the project runs; when the starting tab already matches a project tab it is reused instead of opening a duplicate, and focus is returned to the starting tab after all projects have been opened.

| Parameter      | Description                                                                         |
| -------------- | ----------------------------------------------------------------------------------- |
| `-Project`     | One or more project name(s) to run. Omit to show the interactive multi-select menu. |
| `-InSameShell` | When `$true` (default) reuse the current shell tab; when `$false` open new tabs.    |

```powershell
# Interactive menu (press Enter to accept the first project)
Run-Project

# Run one or more specific projects
Run-Project -Project "MyProject", "OtherProject"

# Open in fresh tabs instead of reusing the current shell
Run-Project -Project "MyProject" -InSameShell:$false
```

**See also:** [Configuration Reference](../configuration/configuration-reference.md)

## [Show-FunctionDetails](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Show-FunctionDetails.ps1)

- **Description:** Renders formatted, color-coded details for a single function: its name, description, and every parameter. Colors are pulled from `ShowFunctionDetailsColors` in `Configuration.psd1`, with a distinct palette color cycled per parameter.
- **Parameters:** -FunctionName, -FunctionInfo
- **Usage:** `Show-FunctionDetails -FunctionName "MyFunction" -FunctionInfo $info`

A presentation helper that is normally driven by `List-Functions` rather than called directly. Given a function name and a metadata hashtable, it writes the name, the `Description` entry (if present), and then each remaining key as a `key => value` line, indenting and coloring each parameter using successive colors from the `ShowFunctionDetailsColors.Parameters` palette. Multi-line values are re-indented to align under their key.

| Parameter       | Description                                                                                                           |
| --------------- | --------------------------------------------------------------------------------------------------------------------- |
| `-FunctionName` | Name of the function being detailed (required).                                                                       |
| `-FunctionInfo` | Hashtable (`IDictionary`) of function metadata, including a `Description` key and one entry per parameter (required). |

```powershell
# Build a metadata hashtable and render it
$info = @{ Description = "Opens browser"; Url = "https://example.com" }
Show-FunctionDetails -FunctionName "Open-Browser" -FunctionInfo $info
```

**See also:** [List-Functions](helper.md)

## [Show-Image](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Show-Image.ps1)

- **Description:** Displays an image file in a Windows Forms dialog. Loads the image from the given path into a PictureBox form whose window size matches the image dimensions. Useful for viewing wallpapers or screenshots.
- **Parameters:** -ImagePath
- **Usage:** `Show-Image -ImagePath "C:\Wallpapers\Mountain.jpg"`, `Show-Image .\Image.png`

## [Test-AdminPrivileges](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-AdminPrivileges.ps1)

- **Description:** Verifies or requests Administrator privileges. With `-CheckOnly` it simply returns a boolean indicating whether the current session is elevated. Without `-CheckOnly`, when not running as admin it warns the user, prompts to open an Administrator PowerShell, and reruns the triggering command (from the current directory) in that elevated shell.
- **Parameters:** -CheckOnly
- **Usage:** `Test-AdminPrivileges`, `if (Test-AdminPrivileges -CheckOnly) { ... }`

When invoked without `-CheckOnly` and the session is not elevated, it captures the current directory and the calling command from the PowerShell call stack, then offers (via `Resolve-Selection`) to relaunch in an Administrator shell that re-runs the original command in place. It throws a `PipelineStoppedException` to halt the non-elevated pipeline. Use `-CheckOnly` as a lightweight, non-interactive guard that returns `$true`/`$false` without prompting or elevating.

| Parameter    | Description                                                                                              |
| ------------ | -------------------------------------------------------------------------------------------------------- |
| `-CheckOnly` | Switch. Return a boolean for whether the session is elevated, without prompting or attempting elevation. |

```powershell
# Guard a function body: stop and offer to re-run elevated if not admin
Test-AdminPrivileges
# Admin-only operations follow...

# Non-interactive check returning a boolean
if (Test-AdminPrivileges -CheckOnly) { Write-Host "Running as admin" }
```

## [Test-AppNotInstalled](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-AppNotInstalled.ps1)

- **Description:** Checks if a Windows Store (AppX) package is not installed. Queries installed AppX packages and returns `$true` if the specified app is not found, or `$false` if it is installed.
- **Parameters:** -appName
- **Usage:** `Test-AppNotInstalled -appName "WindowsTerminal"`

## [Test-HasEfCoreDesign](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-HasEfCoreDesign.ps1)

- **Description:** Reads a project file and checks whether it references the `Microsoft.EntityFrameworkCore.Design` package. Used to determine if a project supports EF Core migrations, e.g. by the EF Core migration wizard when picking a startup project.
- **Parameters:** -projectPath
- **Usage:** `Test-HasEfCoreDesign -projectPath "MyProject.csproj"`, `if (Test-HasEfCoreDesign -projectPath "MyProject.csproj") { ... }`

## [Test-ManifestCompleteness](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-ManifestCompleteness.ps1)

- **Description:** Startup integrity check that warns about function files not exported by their module manifest. For every module under the WinuX Modules root that ships a matching `<Name>.psd1` manifest and a `Functions/` directory, it compares the `.ps1` files on disk against the manifest's `FunctionsToExport` and warns about any function present on disk but missing from its module manifest (i.e. a function that "isn't in its corresponding module" manifest). The fork-owned Custom area (`Modules/Custom`) is checked the same way - its mirror-payload functions must appear in `Custom.psd1`, and a whole fork module is checked against its own manifest. It is the runtime counterpart of the "Manifest Completeness" Pester test, resolving the Modules root from `MachineSpecificPaths.Projects.Self.Modules`. Silent when every function is exported, so it suits a profile startup check alongside `Test-PowerPlan`.
- **Parameters:** (none)
- **Usage:** `Test-ManifestCompleteness`

## [Test-PrivacyStatus](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-PrivacyStatus.ps1)

- **Description:** Performs comprehensive privacy verification for VPN connections with optional Tor support. Validates VPN adapter status, VPN routing (OpenVPN split routes `0.0.0.0/1 + 128.0.0.0/1` and standard `0.0.0.0/0` default routes), current IP visibility, DNS leak detection, and IP geolocation. Reports SECURE only when all required checks pass; in VPN mode (default) that means VPN connected, traffic routed through the VPN, IP hidden (or VPN routing active), and DNS secure, while Tor mode (`-UseTor`) additionally verifies Tor exit-node routing. Can run silently to surface output only when issues are detected.
- **Parameters:** -ISPIPAddress, -UseTor, -Silent
- **Usage:** `Test-PrivacyStatus`, `Test-PrivacyStatus -UseTor`, `Test-PrivacyStatus -Silent`, `Test-PrivacyStatus -ISPIPAddress 192.0.2.10`

Auto-retrieves your original ISP IP (via `api.ipify.org`, falling back to `ifconfig.me`) when `-ISPIPAddress` is not supplied, then runs a sequence of checks: VPN process/adapter detection, VPN default-route verification, current public IP, Tor status (Tor mode only), DNS leak detection, and GeoIP location. It prints a color-coded Privacy Status Report ending in an overall `[SECURE]` or `[NOT SECURE]` verdict with specific remediation guidance. Geolocation is informational only and does not affect the verdict. Network requests route through Tor when `-UseTor` is set, via the helper `Invoke-PrivacyRequest`.

| Parameter       | Description                                                                                                           |
| --------------- | --------------------------------------------------------------------------------------------------------------------- |
| `-ISPIPAddress` | Your original ISP IP for comparison against the current public IP. Optional; retrieved automatically if omitted.      |
| `-UseTor`       | Routes checks through Tor and additionally validates Tor exit-node connectivity.                                      |
| `-Silent`       | Suppresses output entirely when the status is SECURE; only reports when NOT SECURE. Ideal for profile startup checks. |

```powershell
# Full privacy verification in VPN mode (default)
Test-PrivacyStatus

# Verify Tor routing in addition to VPN checks
Test-PrivacyStatus -UseTor

# Quiet startup check: only prints if something is wrong
Test-PrivacyStatus -Silent

# Compare against a known ISP IP instead of auto-detecting
Test-PrivacyStatus -ISPIPAddress 192.0.2.10
```

**See also:** [Invoke-PrivacyRequest](helper.md), [Invoke-TorRequest](helper.md)

## [Test-RegistryValue](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-RegistryValue.ps1)

- **Description:** Verifies that a registry value matches expected content. Reads the registry entry at the specified path and compares it against the expected value, returning `$true` on a match and `$false` if the value is not found or does not match.
- **Parameters:** -Path, -Name, -ExpectedValue
- **Usage:** `Test-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ExpectedValue 'C:\my.jpg'`

All three parameters are mandatory. The function wraps `Get-ItemProperty` in a try/catch, so a missing key or value never throws; it simply returns `$false`, making the function safe to call directly inside an `if` condition.

| Parameter        | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `-Path`          | Registry path (e.g., `HKCU:\Software\...`).           |
| `-Name`          | Registry value name.                                  |
| `-ExpectedValue` | Expected value to compare the registry entry against. |

```powershell
# Confirm a registry value matches before acting on it
if (Test-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ExpectedValue 'C:\my.jpg') {
    Write-Host "Wallpaper set"
}
```

## [Test-WindowTitleCandidates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-WindowTitleCandidates.ps1)

- **Description:** Tests a window title against a list of candidate strings using case-insensitive, regex-escaped matching, returning `$true` on the first match. Used for robust window detection in automation tasks (e.g. by `Close-Project`).
- **Parameters:** -WindowTitle, -Candidates
- **Usage:** `Test-WindowTitleCandidates -WindowTitle "MyProject - Visual Studio Code" -Candidates @("MyProject", "MyRepo")`

Iterates the `-Candidates` array, skipping null/whitespace entries, and matches each against `-WindowTitle` with a case-insensitive (`(?i)`) regex built from `[regex]::Escape()` so candidate values are treated literally. Returns `$true` as soon as any candidate is found in the title, otherwise `$false`.

| Parameter      | Description                                                                          |
| -------------- | ------------------------------------------------------------------------------------ |
| `-WindowTitle` | The actual window title string to test.                                              |
| `-Candidates`  | Array of candidate strings to match against (each is regex-escaped before matching). |

```powershell
# Detect an editor window for a given project
if (Test-WindowTitleCandidates -WindowTitle "MyProject - Visual Studio Code" -Candidates @("MyProject", "MyRepo")) {
    Write-Host "Found window"
}
```

## [Test-WSLDistributionInstalled](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-WSLDistributionInstalled.ps1)

- **Description:** Tests whether the configured WSL distribution (the `DefaultWSLDistribution` key in `Configuration.psd1`) is installed on the system. Returns `$true` if the distribution is present, `$false` otherwise.
- **Usage:** `Test-WSLDistributionInstalled`

Reads `DefaultWSLDistribution` from `Configuration.psd1` and scans the output of `wsl -l`, matching the distribution name with or without the `(Default)` marker. If the key is missing from the configuration, or an error occurs while querying WSL, it reports the problem and returns `$false`.

```powershell
# Returns $true if the configured WSL distribution is installed, $false otherwise
Test-WSLDistributionInstalled
```

## [Test-WSLEnabled](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Test-WSLEnabled.ps1)

- **Description:** Checks whether Windows Subsystem for Linux is installed and available. Runs `wsl --status` and returns `$false` if WSL is not installed, otherwise `$true`.
- **Usage:** `Test-WSLEnabled`, `if (Test-WSLEnabled) { Write-Host "WSL is ready" }`

## [Write-ManualInstructionsToDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Helper/Functions/Write-ManualInstructionsToDesktop.ps1)

- **Description:** Writes formatted manual setup instructions to a text file on the user's Desktop, with a title, an underline separator, the body content, and a generated timestamp. A generic helper for saving complex steps when automation isn't feasible or when automatic configuration fails.
- **Parameters:** -FileName, -Title, -Content
- **Usage:** `Write-ManualInstructionsToDesktop -FileName "setup-instructions.txt" -Title "MyProject Setup" -Content "1. Do this...`n2. Then that..."`

The file is created at the current user's Desktop (resolved via `[Environment]::GetFolderPath("Desktop")`) and written as UTF-8, overwriting any existing file of the same name. The layout is the title, a separator line of `=` characters matching the title length, a blank line, the supplied content, and a trailing `Generated: <yyyy-MM-dd HH:mm:ss>` timestamp. All three parameters are mandatory.

| Parameter   | Description                                                    |
| ----------- | -------------------------------------------------------------- |
| `-FileName` | Filename for the Desktop file (e.g. `setup-instructions.txt`). |
| `-Title`    | Document title, shown at the top above an `=` separator line.  |
| `-Content`  | Main body content with the instructions.                       |

```powershell
# Save manual setup steps to the Desktop
Write-ManualInstructionsToDesktop -FileName "VPN-Setup.txt" -Title "VPN Configuration" -Content "1. Download the VPN client...`n2. Install and configure..."
```

## Configuration

### Loading Spinners

Spinner styles are configured in `Configuration.psd1`:

```powershell
LoadingSpinners = @{
    "Dots" = @{
        Symbols = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
        Delay   = 50
    }
    "Moon" = @{
        Symbols = @("🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘")
        Delay   = 50
    }
    # ... more spinners
}

DefaultSpinner = "Dots"
```

### Function Colors

Output colors are configurable:

```powershell
ListFunctionsColors = @{
    Border             = "DarkCyan"
    DiscrepancyError   = "Red"
    DiscrepancySuccess = "Green"
}

ShowFunctionDetailsColors = @{
    FunctionName = "DarkCyan"
    Description  = "Gray"
    Parameters   = @("Cyan", "DarkCyan", "Blue", "DarkBlue")
}
```

## Common Patterns

### Path Resolution

```powershell
# Get project path
$projectRoot = $global:MachineSpecificPaths.Projects.MyProject.Root

# Navigate to project
Set-Location $projectRoot
```

### Admin Check Pattern

```powershell
function My-AdminFunction {
    Test-AdminPrivileges  # Throws if not admin

    # Admin-only operations...
}
```

### Long Operation Pattern

```powershell
Loading-Spinner -Function {
    # Long operation
    Install-Package ...
} -Label "Installing..."
```

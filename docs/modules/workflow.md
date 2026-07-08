# Workflow Module

The Workflow module **orchestrates complex operations** like opening workspaces and projects with all their associated tools.

## [Close-BrowserTabsByPattern](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Close-BrowserTabsByPattern.ps1)

- **Description:** Helper that closes all browser tabs whose titles match one or more regex patterns. Cycles through every tab in each matching browser window using keyboard navigation (Ctrl+Tab to move, Ctrl+W to close) and supports Chrome, Edge, and Firefox. Firefox windows (where each tab is process-isolated as its own window) are closed directly via a `WM_CLOSE` message. Returns the count of closed tabs. Used by `Close-Project` to close Swagger tabs regardless of which tab is currently focused.
- **Parameters:** -ProcessName, -TitlePatterns
- **Usage:** `Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger")`, `Close-BrowserTabsByPattern -ProcessName "msedge" -TitlePatterns @("(?i)localhost:5000")`

For each browser window it first checks the window title against the patterns (handling Firefox's per-tab windows), closing it directly when it matches. Otherwise it activates the window and cycles through tabs with Ctrl+Tab, closing any whose title matches with Ctrl+W, until it loops back to an already-seen title or hits the per-window safety limit of 30 tabs.

| Parameter        | Description                                                               |
| ---------------- | ------------------------------------------------------------------------- |
| `-ProcessName`   | The browser process name (e.g. `chrome`, `msedge`, `firefox`). Mandatory. |
| `-TitlePatterns` | Array of regex patterns matched against tab/window titles. Mandatory.     |

```powershell
# Close all Chrome tabs whose title contains "swagger" or a failed page load
Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger", "(?i)problem.*loading.*page")

# Verbose diagnostic output
Set-LogLevel Verbose { Close-BrowserTabsByPattern -ProcessName "msedge" -TitlePatterns @("(?i)localhost:5000") }
```

**See also:** [Close-Project](#close-project)

## [Close-Project](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Close-Project.ps1)

- **Description:** Closes all project-specific resources opened by `Open-Project` (Visual Studio windows, VSCode windows, Windows Terminal tabs, and browser tabs/windows), enabling fast switching between projects by closing only project-specific resources while keeping workspace-level applications running. If no project is given, an interactive selection menu is shown.
- **Parameters:** -Project
- **Usage:** `Close-Project`, `Close-Project MyProject`, `Close-Project -Project MyProject, OtherProject`
- **Implementation Note:** Uses Helper-module support functions to resolve configured solution/folder paths into real window-title candidates before matching Visual Studio and VS Code windows.

Projects must be defined in `$Configuration.Projects`; their resources are described by `$Configuration.ProjectActions`. For each selected project the function closes:

- **Visual Studio** windows matched by solution name (resolved via `VisualStudioSolutions`).
- **VSCode** windows matched by folder name (resolved via `VSCodeProjects`).
- **Terminal tabs** named after the project (e.g. `MyProject.Api`, `MyProject.Ui`), delegated to `Close-ProjectTerminals` which sends Ctrl+W to matching tabs.
- **Browser tabs** in the configured `Universal.DefaultBrowser` whose titles contain the project name. If a `Swagger` entry under `BrowserGroups` matches the project, it also closes tabs titled "Swagger UI" (backend running) or, for localhost URLs, "Problem loading page" (backend not running). Closing is delegated to `Close-BrowserTabsByPattern`, which cycles through all tabs so it works even when a different tab is focused.

After closing, `Focus-TerminalTab` refocuses Windows Terminal. Resolving configured paths to window-title candidates makes matching reliable when the project key differs from the actual solution/folder name shown in the title (e.g. `MyProjectKey` vs `My.Project.Solution` / `Project`).

| Parameter  | Description                                                                                                                |
| ---------- | -------------------------------------------------------------------------------------------------------------------------- |
| `-Project` | One or more project names to close (must exist in `$Configuration.Projects`). Omit to show the interactive selection menu. |

```powershell
# Interactive menu to select project(s) to close
Close-Project

# Close all resources for a single project
Close-Project MyProject

# Close resources for multiple projects at once
Close-Project -Project MyProject, OtherProject

# Verbose diagnostic output
Set-LogLevel Verbose { Close-Project MyProject }
```

**See also:** [Close-ProjectTerminals](workflow.md#close-projectterminals)

## [Close-ProjectTerminals](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Close-ProjectTerminals.ps1)

- **Description:** Closes all Windows Terminal tabs matching a specific project name pattern. Cycles through terminal tabs using Ctrl+Tab and closes tabs whose titles match `ProjectName.*` (e.g., `MyProject.Api`, `MyProject.Ui`) with Ctrl+W, skipping the tab it is running from. When provided, it targets the original Windows Terminal window via handle/title so focus changes from Docker startup do not affect a different terminal window, then refocuses the starting tab when done. Used by both Close-Project and Run-Project to prevent duplicate tabs. Returns the count of closed tabs.
- **Parameters:** -ProjectName, -TerminalWindowHandle, -StartingTabTitle
- **Usage:** `Close-ProjectTerminals -ProjectName MyProject`
- **Implementation Note:** Relies on the Helper-module helper Get-TargetTerminalWindow to bind tab-closing operations to the intended Windows Terminal instance.

When `Run-Project` triggers a Docker cold start, Docker Desktop can temporarily steal focus. `Close-ProjectTerminals` therefore accepts optional internal coordination inputs (`-TerminalWindowHandle` and `-StartingTabTitle`) so it can keep operating on the original Windows Terminal window instead of whichever terminal window is foreground at that moment. Because `Open-Terminal` uses `--suppressApplicationTitle`, tab names are preserved even while child processes (npm, node, dotnet) are running, so matching tabs can be closed directly. A safety limit of 20 tab cycles prevents runaway loops.

| Parameter               | Description                                                                    |
| ----------------------- | ------------------------------------------------------------------------------ |
| `-ProjectName`          | Project prefix used to match tab titles like `MyProject.Api` (mandatory).      |
| `-TerminalWindowHandle` | Optional internal handle used to target a specific Windows Terminal instance.  |
| `-StartingTabTitle`     | Optional internal starting tab title used to restore focus after closing tabs. |

```powershell
# Close all tabs named MyProject.* (e.g., MyProject.Api, MyProject.Ui)
Close-ProjectTerminals -ProjectName MyProject

# Verbose diagnostic output
Set-LogLevel Verbose { Close-ProjectTerminals -ProjectName MyProject }
```

**See also:** [Close-Project](#close-project), [Run-Project](helper.md#run-project), [Focus-TerminalTab](#focus-terminaltab)

## [DockerWizard](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/DockerWizard.ps1)

- **Description:** Starts or stops Docker Desktop with loading-spinner feedback, daemon readiness detection, graceful Docker Desktop CLI integration, and Docker-owned WSL cleanup. When starting, it can clean up a partial Docker state, launch Docker Desktop in detached mode (falling back to `Open-Docker`), wait up to 180 seconds for `docker info` to succeed, and optionally start Docker Compose services from an explicit compose file path or a project directory. When stopping, it first requests a graceful shutdown and then force-cleans Docker-owned helper processes and `docker-desktop` WSL distros only if Docker gets stuck. Used by `Run-Project` to transparently spin up database containers before launching project servers.
- **Parameters:** -Stop, -ComposeProjectPath, -ComposeFilePath
- **Usage:** `DockerWizard`, `DockerWizard -Stop`, `DockerWizard -ComposeProjectPath "<DevRoot>\MyProject"`, `DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"`

`DockerWizard` treats Docker Desktop as more than a single Windows process. It also checks for Docker-owned `wsl.exe` helper processes and terminates `docker-desktop` WSL distros when Docker is stuck in a partial `starting` state. On start it polls for daemon readiness (up to 180s); on stop it requests a graceful shutdown and only escalates to force-cleanup if the shutdown stalls (up to 60s).

| Parameter             | Description                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Stop`               | Stops Docker Desktop: requests a graceful shutdown, then force-cleans Docker-owned WSL distros and helper processes if the shutdown stalls. |
| `-ComposeProjectPath` | Project directory to start Compose services from; looks for `docker-compose.yml` or `compose.yml` inside it.                                |
| `-ComposeFilePath`    | Explicit Docker Compose file path; used directly, taking precedence over `-ComposeProjectPath`.                                             |

```powershell
# Start Docker Desktop and wait for the daemon to become ready
DockerWizard

# Stop Docker Desktop cleanly
DockerWizard -Stop

# Start Docker and spin up Compose services from a project directory
DockerWizard -ComposeProjectPath "<DevRoot>\MyProject"

# Start Docker and spin up Compose services from a specific compose file
DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"
```

**See also:** [Kill-All](system.md#kill-all)

## [EfCoreMigrationWizard](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/EfCoreMigrationWizard.ps1)

- **Description:** Interactive, menu-driven Entity Framework Core migration manager for a .NET solution. Searches up and down from the current directory to locate the nearest `.sln`, then discovers migration projects (dedicated `*.Migrations` csproj files or any project containing a `*ModelSnapshot.cs`), detects the active database provider from appsettings (PostgreSQL, Oracle, SqlServer), and resolves the startup project and DbContext. Offers menu options to add, remove, redo, squash, and sync migrations across database projects.
- **Usage:** `EfCoreMigrationWizard`, `efm`
- **Alias:** efm

Discovery work is delegated to focused Helper-module functions (`Find-EfMigrationProjects`, `Get-EfCurrentDatabaseType`, `Find-EfStartupProject`, `Resolve-EfMigrationDbContext`, `Get-EfMigrations`). DbContext resolution is optimized for the common case: when a migrations project has a single `ModelSnapshot` (one DbContext), commands run without `--context` and the slow `dotnet ef dbcontext list` design-time build is skipped; ambiguous or absent cases fall back to a project source scan plus design-time discovery, prompting for selection only when multiple contexts exist. Project and startup paths are normalized to the solution root for reliable `dotnet ef` execution.

The menu adapts to the current state (e.g. redo and remove only appear when migrations exist, sync only when multiple migration projects are present):

| Option                              | Behavior                                                                                                                 |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Add new migration                   | Prompts for a name and runs `dotnet ef migrations add`.                                                                  |
| Redo last migration                 | Reverts the database to the previous migration, removes the last migration, then re-adds it with the same name.          |
| Remove last migration               | Reverts the database to the previous migration (or initial state), then runs `dotnet ef migrations remove`.              |
| Squash all migrations               | Deletes all migration files and creates a single `initial-migration`. Intended for use before an app reaches production. |
| Sync migration to other database(s) | Generates an equivalent migration in other discovered database projects, setting the correct provider flag per target.   |

```powershell
# Open the wizard in the context of the nearest solution file
EfCoreMigrationWizard

# Same, via alias
efm
```

> [!TIP]
> If migration creation fails with "No DbContext named ...", rerun the wizard after a profile reload. The wizard prefers EF CLI-discovered design-time contexts over stale snapshot names.

## [Focus-TerminalTab](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Focus-TerminalTab.ps1)

- **Description:** Helper that focuses Windows Terminal and optionally navigates to a specific tab by title. Activates the Windows Terminal window and, if a `-TargetTitle` is provided, cycles through tabs with Ctrl+Tab until the matching tab is found and focused. Uses `AppActivate` with a `SetForegroundWindow` fallback when the process ID is stale. Used by Close-Project and Close-ProjectTerminals to refocus the starting tab after operations.
- **Parameters:** -TargetTitle, -Quiet
- **Usage:** `Focus-TerminalTab`, `Focus-TerminalTab -TargetTitle "PowerShell"`

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| `-TargetTitle` | Title of the tab to focus. Omit to only activate the Windows Terminal window without switching tabs. |
| `-Quiet`       | Switch. Suppresses the informational output while focusing.                                          |

```powershell
# Activate Windows Terminal without switching tabs
Focus-TerminalTab

# Activate Windows Terminal and cycle to the tab titled "PowerShell"
Focus-TerminalTab -TargetTitle "PowerShell"
```

## [Open-DnD](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-DnD.ps1)

- **Description:** Opens the full D&D campaign workspace for a tabletop RPG session: the Obsidian vault with campaign notes, the rulebook PDF in Acrobat, and the spell/resource URLs in the browser. The campaign is chosen from the `Campaigns` array in `Configuration.psd1` via an interactive menu when not specified, and `-FoundryVTT` additionally launches the FoundryVTT game server.
- **Parameters:** -Campaign, -FoundryVTT
- **Usage:** `Open-DnD`, `Open-DnD -Campaign "ExampleCampaign"`, `Open-DnD -Campaign "AnotherCampaign" -FoundryVTT`
- **Campaigns:** ExampleCampaign, AnotherCampaign

Selects a campaign from `Configuration.psd1` (`Campaigns`) and, per campaign, opens Obsidian, the configured rulebook PDF via `Open-Acrobat`, and the matching spell/resource browser group via `Open-Browser`. When `-FoundryVTT` is given, the FoundryVTT virtual tabletop server is started first via `Open-FoundryVTT`. Omitting `-Campaign` shows the selection menu; if no campaign is chosen the function reports it and exits without opening anything.

| Parameter     | Description                                                                                                                   |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `-Campaign`   | Name of the campaign to open, as defined in the `Campaigns` configuration array. Omit to show the interactive selection menu. |
| `-FoundryVTT` | Also launches the FoundryVTT virtual tabletop server.                                                                         |

```powershell
# Show the campaign selection menu, then open all campaign tools
Open-DnD

# Open a specific campaign directly (Obsidian, rulebook PDF, browser resources)
Open-DnD -Campaign "ExampleCampaign"

# Open a campaign and also start the FoundryVTT server
Open-DnD -Campaign "AnotherCampaign" -FoundryVTT
```

**See also:** [Open-Browser](application.md#open-browser), [Open-Acrobat](application.md#open-acrobat)

## [Open-Project](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-Project.ps1)

- **Description:** Opens a development project with all its configured tools, applications and terminal tabs. Reads the project's action list from `ProjectActions` in `Configuration.psd1` and executes each action in order; with `-RunApp` it starts the project's server instead of opening terminal tabs. Omit the project name to pick from an interactive menu.
- **Parameters:** -Project, -RunApp, -VSCodeWorkspace
- **Usage:** `Open-Project`, `Open-Project MyProject`, `Open-Project MyProject -RunApp`
- **Projects:** MyProject, OtherProject (the entries of the `Projects` array in `Configuration.psd1`)

Each action in `ProjectActions` is a named PowerShell function (e.g. `Open-VSCode`, `Open-VisualStudio`, `Open-Browser`) whose parameters are resolved at runtime. The `{ProjectName}` placeholder in any action parameter is replaced with the actual project name at execution time. When no project name is supplied, an interactive menu lists every project in the `Projects` array; multiple projects may be selected and each is opened in sequence. The special action `Open-ProjectTerminals-Or-RunProject` is context-sensitive: with `-RunApp` it starts the server via `Run-Project`, otherwise it opens terminal tabs via `Open-ProjectTerminals`. When `-VSCodeWorkspace <name>` is set, the project's `Open-VSCode` action opens the given `.code-workspace` (via `Open-VSCodeWorkspace`) in place of the project folder. The function returns the list of project names that were opened.

| Parameter          | Description                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Project`         | One or more project names from the `Projects` configuration array. Omit to show the interactive selection menu.                            |
| `-RunApp`          | Starts the project's runnable app instead of opening terminals (applies to the `Open-ProjectTerminals-Or-RunProject` action only).         |
| `-VSCodeWorkspace` | When set, the project's `Open-VSCode` action opens the given `.code-workspace` (via `Open-VSCodeWorkspace`) instead of the project folder. |

```powershell
# Interactive project selection menu
Open-Project

# Open a project with all its configured actions
Open-Project MyProject

# Open a project and start its application server
Open-Project MyProject -RunApp
```

A project's behavior is defined by its `ProjectActions` entry in `Configuration.psd1`:

```powershell
ProjectActions = @{
    MyProject = @(
        @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "MySolution" } }
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyRepo" } }
        @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = "GroupName" } }
    )
}
```

**See also:** [Open-ProjectTerminals](#open-projectterminals), [Open-Workspace](#open-workspace)

## [Open-ProjectTerminals](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-ProjectTerminals.ps1)

- **Description:** Opens project-specific Windows Terminal tabs based on `Configuration.ProjectTerminals`, with automatic tab naming (`ProjectName.PathKey`, e.g. `MyProject.Api`, `WinuX.Root`), optional onefetch repository info, and flexible focus control. Smart idempotency checks all Windows Terminal windows: if every expected tab already exists it warns and skips (unless `-Force`), and if only some exist it opens just the missing ones in the current window. Window grouping is controlled by `-InSameShell` and `-InSameGroup`, and when `-InSameShell` is omitted the function auto-detects whether to reuse the single open window or start a new one to keep project groups separate.
- **Parameters:** -Project, -InvokeOnefetch, -InSameShell, -InSameGroup, -FocusTab, -Force
- **Usage:** `Open-ProjectTerminals`, `Open-ProjectTerminals -Project "MyProject"`, `Open-ProjectTerminals -Project "MyProject", "OtherProject" -InSameShell`, `Open-ProjectTerminals -Project "MyProject" -FocusTab "origin"`, `Open-ProjectTerminals -Project "MyProject" -FocusTab "MyProject.Api"`, `Open-ProjectTerminals -Project "MyProject", "OtherProject" -InvokeOnefetch:$false`, `Open-ProjectTerminals -Project "MyProject" -Force`
- **Projects:** Defined in `Configuration.ProjectTerminals` (e.g. `MyProject`, `OtherProject`)
- **FocusTab Options:** `"origin"` returns to the original tab where the function was called, `"ProjectName.PathKey"` focuses a specific project tab (e.g. `MyProject.Api`), numeric index focuses the tab at that position (e.g. `"0"` for the first tab)

Reads project definitions from `ProjectTerminals` in `Configuration.psd1`. Each project lists one or more `Paths`; every path opens in its own tab named `ProjectName.PathKey`. Regular path keys resolve through `PathTemplates` via `Resolve-ProjectPath`, while special entries cover shells and explicit locations. When `InvokeOnefetch` is on, each resolved-path tab runs `onefetch` after `Set-Location`. Named-tab focusing navigates with `Ctrl+Shift+Tab` relative to the last created tab, so it applies only when tabs share a window.

| Parameter         | Default  | Description                                                                                    |
| ----------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `-Project`        | -        | One or more project names from `ProjectTerminals`. Omit to show an interactive selection menu. |
| `-InvokeOnefetch` | `$true`  | Runs `onefetch` in each path tab to display repository information.                            |
| `-InSameShell`    | `$false` | Opens tabs in the current Windows Terminal window. Auto-detected when omitted (see below).     |
| `-InSameGroup`    | `$true`  | Groups tabs from different projects into the same window.                                      |
| `-FocusTab`       | `"0"`    | Tab to focus after opening: `"origin"`, a `ProjectName.PathKey` name, or a numeric index.      |
| `-Force`          | `$false` | Bypasses idempotency checks and opens all tabs even if they already exist.                     |

Window grouping combines `-InSameShell` and `-InSameGroup`:

| InSameShell | InSameGroup | Result                                 |
| ----------- | ----------- | -------------------------------------- |
| `$true`     | `$true`     | All tabs in the current window         |
| `$true`     | `$false`    | Each project in its own new window     |
| `$false`    | `$true`     | All projects grouped in one new window |
| `$false`    | `$false`    | Every tab in its own new window        |

Special `Paths` entries:

| Type                   | Example                               | Description                                                       |
| ---------------------- | ------------------------------------- | ----------------------------------------------------------------- |
| Regular string         | `"Api"`                               | Resolves the path from `PathTemplates` via `Resolve-ProjectPath`  |
| `"DEFAULT"`            | `"DEFAULT"`                           | Plain tab at the terminal's default directory (no `Set-Location`) |
| `"WSL"`                | `"WSL"`                               | WSL tab using the configured `DefaultWSLDistribution`             |
| Hashtable with Path    | `@{ Key = "Logs"; Path = "C:\Logs" }` | Tab at an explicit custom path                                    |
| Hashtable without Path | `@{ Key = "Shell" }`                  | Plain tab with a custom name                                      |

```powershell
# Interactive project selection menu
Open-ProjectTerminals

# Open one project; here a multi-path project yields MyProject.Api and MyProject.Ui tabs
Open-ProjectTerminals -Project "MyProject"

# Open two projects, each in its own new window
Open-ProjectTerminals -Project "MyProject", "OtherProject" -InSameShell -InSameGroup:$false

# Open and return focus to the tab the function was called from
Open-ProjectTerminals -Project "MyProject" -FocusTab "origin"

# Skip the onefetch banner in each tab
Open-ProjectTerminals -Project "MyProject", "OtherProject" -InvokeOnefetch:$false

# Re-open even if the tabs already exist (bypass idempotency)
Open-ProjectTerminals -Project "MyProject" -Force
```

**See also:** [Close-ProjectTerminals](workflow.md#close-projectterminals)

## [Open-Training](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-Training.ps1)

- **Description:** Opens the training Word document in Microsoft Word. Launches the file configured at `Universal.TrainingFile` from the machine-specific `TrainingDirectory`. Does nothing if Word (`WINWORD`) is already running.
- **Usage:** `Open-Training`

## [Open-Workspace](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-Workspace.ps1)

- **Description:** The main entry point for starting work. Opens a predefined workspace by executing a configured sequence of actions (projects, browser tab groups, applications, and window layouts) across virtual desktops. Use `-Alongside` to spawn the workspace on new virtual desktops to the right of existing ones, letting multiple workspaces run simultaneously without interfering. In alongside mode the computed desktop offset is injected into the workspace's actions so they land on the new desktops - both `Set-WorkspaceWindowLayout` and the final `Focus-VirtualDesktop` action receive `-DesktopOffset`, so the configured landing (e.g. `DesktopNumber = 1`) focuses the new workspace's own first desktop instead of the original desktop 1. Automatically reconciles the calling terminal tab via `Terminate-WindowsTerminalTabs -OnlyCurrent` (skipped when running alongside or re-running from a same-workspace project tab). Diagnostic output for the workspace and its actions is shown when run under `Set-LogLevel Verbose`.
- **Parameters:** -Workspace, -Project, -Alongside, -VSCodeWorkspace
- **Usage:** `Open-Workspace`, `Open-Workspace MyWorkspace`, `Open-Workspace MyWorkspace MyProject`, `Open-Workspace MyWorkspace -Alongside`, `w dotfiles -VSCodeWorkspace Consolidation`, `w MyWorkspace`
- **Alias:** w

Reads the workspace list from `Configuration.Workspaces` and the per-workspace action sequence from `Configuration.WorkspaceActions`. With no argument it shows an interactive menu (multiple selections allowed); pressing Enter opens the default workspace. A typical workspace opens browser tab groups, the Obsidian vault, the project (Visual Studio, VS Code, terminals), DBeaver, communication apps, and finally applies the window layout. When an `Open-Browser` action runs for a project that has a matching `Swagger` entry under `BrowserGroups`, the relevant Swagger group is auto-added (unless already open) via [Resolve-SwaggerBrowserGroup](#resolve-swaggerbrowsergroup). Any extra `-Name Value` / `-Switch` arguments are forwarded to the underlying actions, with the workspace configuration taking precedence. Passing `-VSCodeWorkspace <name>` (or a bare `-VSCodeWorkspace` for a selection menu, or a `DefaultVSCodeWorkspaces` config entry for the workspace) opens `<name>.code-workspace` in place of the project folder - the resolved name (precedence: command-line value, then the bare-switch menu, then the config default) is passed to the `Open-Project` action, which reroutes `Open-VSCode` to `Open-VSCodeWorkspace`. The window layout needs no coupling to this: VS Code layout entries match by process, so the workspace window lands in the VS Code slot like any other VS Code window.

Everything the flow spawns inherits the invoking shell's token, so running from an **elevated** shell produces elevated app windows (and, if PowerToys is not yet running, an elevated PowerToys) that a non-elevated FancyZones cannot snap. The function logs a warning when it detects an elevated shell and proceeds unchanged - prefer running workspaces from a normal shell.

| Parameter          | Description                                                                                                                                                                                                                                                                         |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Workspace`       | One or more workspace names to open. Omit to show the selection menu.                                                                                                                                                                                                               |
| `-Project`         | Optional project name(s) forwarded to the `Open-Project` action within the workspace.                                                                                                                                                                                               |
| `-Alongside`       | Opens the workspace on new virtual desktop(s) added to the right of existing ones, so multiple workspaces coexist.                                                                                                                                                                  |
| `-VSCodeWorkspace` | Opens `<name>.code-workspace` (from `VSCode\Workspaces`) in place of the project folder. Pass a bare `-VSCodeWorkspace` for a selection menu; omit it to use the `DefaultVSCodeWorkspaces` config entry (if any) or normal folder behaviour. |

```powershell
# Interactive workspace selection menu (Enter = default workspace)
Open-Workspace

# Open a specific workspace by name
Open-Workspace MyWorkspace

# Open a workspace and select the project to open within it
Open-Workspace MyWorkspace MyProject

# Open another workspace on new desktops alongside the current one
Open-Workspace OtherProject -Alongside

# Open a workspace but load a .code-workspace file instead of the project folder
w dotfiles -VSCodeWorkspace Consolidation

# Verbose diagnostic output
Set-LogLevel Verbose { w MyWorkspace }
```

**See also:** [Open-Project](workflow.md#open-project), [Close-Project](workflow.md#close-project), [Open-Browser](../modules/application.md), [Resolve-SwaggerBrowserGroup](#resolve-swaggerbrowsergroup)

## [Resolve-SwaggerBrowserGroup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Resolve-SwaggerBrowserGroup.ps1)

- **Description:** Resolves the `Swagger` browser group for a project so it can be handed to `Open-Browser`. Maps a project name to its entry in the `BrowserGroups` `Swagger` group (case-insensitive match on the entry's `Name`) and returns that group name. By default it also checks whether the project's Swagger tab is already open (via `Test-BrowserGroupAlreadyOpen`) and returns `$null` when it is, so callers never open a duplicate. Returns `$null` when the project has no `Swagger` entry, no project name is supplied, or the tab is already open. This is the Swagger-tab logic that previously lived inline inside `Open-Workspace`, extracted into a standalone function so it can be reused wherever a project's Swagger UI tab needs opening.
- **Parameters:** -Project, -Browser, -CachedBrowserWindows, -SkipDuplicateCheck
- **Usage:** `Resolve-SwaggerBrowserGroup -Project "MyProject"`, `Resolve-SwaggerBrowserGroup -Project $selectedProjects -Browser "Firefox"`, `Resolve-SwaggerBrowserGroup -Project "MyProject" -SkipDuplicateCheck`

`Open-Workspace` calls this for each `Open-Browser` action: it resolves the active project (the explicit `-Project`, otherwise the projects selected by a preceding `Open-Project` action), passes it here, and appends the returned group name to that action's `Groups`. `-Project` accepts an array and uses the first non-empty element. `-Browser` defaults to `Universal.DefaultBrowser`. `-CachedBrowserWindows` forwards a pre-fetched window list to the duplicate check to avoid re-enumerating windows. `-SkipDuplicateCheck` returns the resolved group name without the already-open check (the pure config lookup). A Swagger lookup failure is logged and treated as "no group", so it never aborts the workspace.

| Parameter               | Default                    | Description                                                                                        |
| ----------------------- | -------------------------- | -------------------------------------------------------------------------------------------------- |
| `-Project`              | -                          | Project name to map; an array is accepted and the first non-empty element is used. Mandatory.      |
| `-Browser`              | `Universal.DefaultBrowser` | Browser used for the already-open check.                                                           |
| `-CachedBrowserWindows` | -                          | Pre-fetched window handle list forwarded to `Test-BrowserGroupAlreadyOpen` to skip re-enumeration. |
| `-SkipDuplicateCheck`   | `$false`                   | Returns the resolved group name without the already-open check (pure config lookup).               |

```powershell
# Resolve a project's Swagger group (or $null if it has none / is already open)
$group = Resolve-SwaggerBrowserGroup -Project "MyProject"
if ($group) { Open-Browser $group }

# Pure config lookup, skipping the window/duplicate check
Resolve-SwaggerBrowserGroup -Project "MyProject" -SkipDuplicateCheck
```

**See also:** [Open-Workspace](#open-workspace), [Open-Browser](application.md#open-browser), [Test-BrowserGroupAlreadyOpen](application.md#test-browsergroupalreadyopen)

## [Test-TerminalTabsAlreadyOpen](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Test-TerminalTabsAlreadyOpen.ps1)

- **Description:** Checks which expected terminal tabs are already open by cycling through every Windows Terminal tab across all WT windows with Ctrl+Tab. Returns a PSCustomObject with `AllOpen` (bool) and `FoundTabs` (array) so callers can decide whether to skip entirely or open only the missing tabs. Reports partially open projects with a list of missing tab names.
- **Parameters:** -ExpectedTabNames, -ProjectName
- **Usage:** `$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("MyProject.Root", "MyProject.DOCS") -ProjectName "MyProject"`

A helper used by project-launching workflows to make terminal setup idempotent. It finds all `WindowsTerminal` windows via `Get-WindowHandle`, activates each one with `SetForegroundWindow`, then walks its tabs with `Ctrl+Tab`, matching each tab title against the expected names. It checks up to 20 tabs per window and stops cycling once it loops back to an already-seen title. It exits early once every expected tab has been found. If all tabs are present it prints a yellow "already open" notice; if only some are present it warns and lists the missing tabs. When Windows Terminal is not running (or no windows are found), it safely returns `AllOpen = $false` with an empty `FoundTabs`.

| Parameter           | Description                                                                                               |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| `-ExpectedTabNames` | Array of tab names to check for (e.g. `@("MyProject.Root", "MyProject.Api", "MyProject.Ui")`). Mandatory. |
| `-ProjectName`      | Project name used in the status / warning messages. Mandatory.                                            |

Returns a `PSCustomObject` with:

- `AllOpen` (bool) - `$true` if every expected tab was found
- `FoundTabs` (array) - the tab names that were found

```powershell
# Check whether all of a project's terminal tabs are already open
$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("MyProject.Root", "MyProject.DOCS") -ProjectName "MyProject"

if ($result.AllOpen) {
    Write-Host "All tabs exist, skipping"
}
elseif ($result.FoundTabs.Count -gt 0) {
    # Open only the tabs that are still missing
    Write-Host "Some tabs open: $($result.FoundTabs -join ', ')"
}
```

## [Training-Backup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Training-Backup.ps1)

- **Description:** Runs the external training backup batch script in its configured directory. Navigates to `$MachineSpecificPaths.TrainingBackupDirectory`, executes `TrainingBackup.bat` (which backs up the training document to its configured destinations), and restores the original working directory on exit.
- **Usage:** `Training-Backup`

The backup script and its directory live outside this WinuX repository, so the actual backup destinations and processing are defined there. The function wraps the call so the original working directory is always restored via a `finally` block, and reports success or the captured error message.

```powershell
# Run the training backup script
Training-Backup
```

## Parameter Forwarding

`Open-Workspace` (and the action-driven workflows it dispatches) supports **intelligent parameter forwarding**: any extra parameters you pass on the command line beyond `Workspace` and `Project` are automatically forwarded only to the actions that actually accept them. This lets you steer individual actions ad-hoc, without editing `Configuration.psd1` or touching any function signatures.

### How it works

1. Extra parameters (beyond `Workspace` and `Project`) are captured via `ValueFromRemainingArguments`.
2. They are parsed into a hashtable supporting both `-Param Value` and `-Switch` forms (a bare switch is recorded as present without consuming a following value).
3. Before each action runs, `Get-Command` inspects that target action's declared parameters.
4. `Get-FilteredParams` keeps only the parameters the action **explicitly declares** and splats just those into the call.
5. Unknown parameters are silently filtered out: no errors are raised, and existing functions need no modification.

### Examples

```powershell
# Pass -Machine straight through to the action that declares it; others ignore it
w MyWorkspace -Machine MyMachine

# Multiple extra parameters work too (a value param and a bare switch)
w MyWorkspace -CustomParam Value -SomeSwitch
```

### Worked example

When running `w MyWorkspace -Machine MyMachine`, each action in the workspace sequence is checked independently:

- `Send-WakeOnLan` receives `-Machine MyMachine` (it declares a `$Machine` parameter).
- `Open-Browser` does NOT receive `-Machine` (filtered out, no such parameter).
- `Open-Project` does NOT receive `-Machine` (filtered out).
- `Set-WorkspaceWindowLayout` does NOT receive `-Machine` (filtered out).

Only the one action that declares `$Machine` sees the value; every other action runs exactly as configured. Because the workflow determines per-action which parameters each function can accept, you do **not** need to modify any existing functions to take advantage of forwarding.

## Configuration

### Workspace Configuration

```powershell
# Available workspaces
Workspaces = @(
    "MyRepo"
    "MyWorkspace"
    "OtherProject"
)

# Actions per workspace
WorkspaceActions = @{
    MyWorkspace = @(
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub", "Seq") } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") ; Instances = 3 } }  # Opens exactly 3 Google windows (rerun-safe)
        @{ Action = "Open-Obsidian" }
        @{ Action = "Open-Project" }
        @{ Action = "Open-DBeaver" }
        @{ Action = "Open-WhatsApp" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
    )
}
```

### Project Configuration

```powershell
# Path templates
Projects = @{
    MyProject = @{
        Root     = "{Dev}\MyWorkspace\MyProject"
        Solution = "{Dev}\MyWorkspace\MyProject\MyProject.sln"
        Api      = "{Dev}\MyWorkspace\MyProject\src\Api"
        WebMVC   = "{Dev}\MyWorkspace\MyProject\src\WebMVC"
        WebWasm  = "{Dev}\MyWorkspace\MyProject\src\WebWasm"
    }
}

# Terminal paths
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("Api", "WebMVC", "WebWasm") }
    @{ Name = "Server"; BasePath = "Projects.Server"; Paths = @("DEFAULT", "WSL") }
)

# Run commands
RunnableProjectMappings = @(
    @{ Name = "MyProject"; Commands = @("dnr", "dnr", "dnr") }
)
```

## Action Types Reference

| Action                                | Description                                                           |
| ------------------------------------- | --------------------------------------------------------------------- |
| `Open-Browser`                        | Opens browser with URL groups (supports `Instances` for multi-window) |
| `Open-Obsidian`                       | Opens Obsidian vault                                                  |
| `Open-Project`                        | Opens a project (can nest)                                            |
| `Open-VSCode`                         | Opens VS Code                                                         |
| `Open-VisualStudio`                   | Opens Visual Studio                                                   |
| `Open-DBeaver`                        | Opens DBeaver                                                         |
| `Open-WhatsApp`                       | Opens WhatsApp                                                        |
| `Open-Outlook`                        | Opens Outlook                                                         |
| `Open-Discord`                        | Opens Discord                                                         |
| `Open-ProjectTerminals-Or-RunProject` | Opens terminals or runs servers                                       |
| `Set-WorkspaceWindowLayout`           | Applies window layout                                                 |
| `Terminate-WindowsTerminalTabs`       | Closes terminal tabs (e.g., `-OnlyCurrent` to close calling tab)      |
| `Return`                              | Stops action processing                                               |

> Swagger is not a standalone action. When an `Open-Browser` action runs in a workspace, the active project's `Swagger` group is auto-added via [Resolve-SwaggerBrowserGroup](#resolve-swaggerbrowsergroup) (unless it is already open).

## Parameter Substitution

Use `{ProjectName}` for dynamic values:

```powershell
ProjectActions = @{
    MyProject = @(
        @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
    )
}
# {ProjectName} replaced with "MyProject" at runtime
```

## Typical Workflows

### Start of Day (Work)

```powershell
w MyWorkspace MyProject run
```

1. Opens Firefox with AI/GitHub/Seq tabs
2. Opens Obsidian
3. Opens MyProject project (VS, VS Code)
4. Opens terminals and starts servers
5. Opens DBeaver
6. Opens WhatsApp
7. Applies window layout (everything positioned)

### Quick Learning Session

```powershell
w OtherProject
```

1. Opens browser with documentation/tutorials
2. Opens Obsidian for notes
3. Opens VS Code with learning project
4. Applies learning layout

### Just Open a Project

```powershell
Open-Project MyProject
```

1. Opens Visual Studio with MyProject.sln
2. Opens VS Code with MyRepo
3. Opens terminal tabs

### End of Day Cleanup

```powershell
Close-Project MyProject
# Closes all MyProject-related windows and tabs
```

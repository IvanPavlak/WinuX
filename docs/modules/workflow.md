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
- **Implementation Note:** Uses Helper-module support functions to resolve configured solution/folder paths into real window-title candidates before matching Visual Studio and VS Code windows; Swagger tab patterns are delegated to `Get-SwaggerCloseTitlePatterns`.

Projects must be defined in `$Configuration.Projects`; their resources are described by `$Configuration.ProjectActions`. For each selected project the function closes:

- **Visual Studio** windows matched by solution name (resolved via `VisualStudioSolutions`).
- **VSCode** windows matched by folder name (resolved via `VSCodeProjects`).
- **Terminal tabs** named after the project (e.g. `MyProject.Api`, `MyProject.Ui`), delegated to `Close-ProjectTerminals` which sends Ctrl+W to matching tabs.
- **Browser tabs** in the configured `Universal.DefaultBrowser` whose titles contain the project name. If a `Swagger` entry under `BrowserGroups` matches the project, it also closes tabs titled "Swagger UI" (backend running) or, for localhost URLs, "Problem loading page" (backend not running) - those extra patterns come from [Get-SwaggerCloseTitlePatterns](#get-swaggerclosetitlepatterns) and are empty for a project with no `Swagger` entry. Closing is delegated to `Close-BrowserTabsByPattern`, which cycles through all tabs so it works even when a different tab is focused.

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

## [Close-Workspace](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Close-Workspace.ps1)

- **Description:** The counterpart to `Open-Workspace`, one level above `Close-Project`: closes every window and every Windows Terminal tab that a workspace open produced. Where `Close-Project` closes one project's resources and deliberately leaves workspace-level applications running, this tears the whole workspace down. Ownership comes from the tracker `Open-Workspace` writes, never from `WorkspaceActions` - configuration cannot express which *instance* of a shared application belongs to which workspace, and guessing is what this exists to avoid. If no workspace is given, an interactive menu lists the workspaces currently tracked as open.
- **Parameters:** -Workspace, -StatePath, -WhatIf
- **Alias:** cw
- **Usage:** `Close-Workspace`, `Close-Workspace Server`, `Close-Workspace -Workspace Server, WinuX`, `Close-Workspace Server -WhatIf`
- **Implementation Note:** Reads [Get-WorkspaceState](#get-workspacestate); closes windows with `WM_CLOSE` and terminal tabs through their UI Automation close button; verifies with [Wait-WindowsClosed](window.md#wait-windowsclosed); rewrites the tracker with [Save-WorkspaceState](#save-workspacestate).

### Where ownership comes from

Every `Open-Workspace` invocation records what it actually opened - a before/after diff of the windows on screen and of the Windows Terminal tab strip - as one tracker entry (see [Get-WorkspaceOpenDelta](#get-workspaceopendelta)). `Close-Workspace` closes exactly what that entry lists, and nothing else.

That single fact delivers the single-instance guarantee for free. Obsidian launched by workspace A is already running when B is opened alongside, so B's `Open-Obsidian` action creates no window, so Obsidian never enters B's record, so closing B leaves it running.

A **plain** open additionally claims what was already on screen when it finishes, because it reset the virtual desktops first - the screen *is* that workspace. That is what stops an application which was already running from surviving every teardown forever: it produced no new window to diff, so a strict diff would never record it, it would still be running at the next open, and it would never become closable. An **`-Alongside`** open never claims, because it adds to a screen other workspaces are already using and taking their windows would let closing this one close theirs. Processes named in `Universal.VisibleWindowExclusions` - the same list `Kill-All` uses to decide what a blunt teardown leaves alone - are never claimed that way, so a plain open does not take ownership of the terminal window it was typed in, of Rainmeter, or of anything else that merely happened to be running. A window the open genuinely *created* is always recorded, whatever its process is called.

With no tracker at all - a workspace opened before this feature existed, from another session, or left over from before a reboot - the command says so and stops, rather than falling back to `WorkspaceActions`, which would reintroduce exactly the ownership ambiguity the tracker removes.

### The second claim: the workspace's own virtual desktops

A workspace owns the virtual desktops it opened on, so **a window sitting on one of them belongs to it** even when the diff never recorded it - a browser window that was already open and got reused, a dialog an action spawned indirectly, anything that had no top-level window yet when the snapshot was taken. This is what makes "everything on that workspace's desktops goes" true rather than approximately true, and it is also what tells the teardown which desktops to remove.

Which desktops those are is resolved from **where the workspace's own windows are standing at teardown time**, never from a stored index. Desktop indexes shift whenever a desktop to their left is removed, so a stored one goes stale, and acting on a stale index would reach onto another workspace's desktop. Handles are stable, so resolving them live ([Get-WindowDesktopIndex](window.md#get-windowdesktopindex)) is the one answer that cannot be wrong. Desktops belonging to a workspace that stays open are excluded from both halves of this - the claim and the removal.

### What a teardown does

- **Windows** are matched by recorded handle, then re-resolved by process id + process name (Electron applications recreate their window without restarting), then by process name + **exact** title (the application restarted outright). A record that named no process is never matched on title alone - a title is not evidence of ownership.
- **A window matched by its own live handle is unambiguously this workspace's.** The survivor guard - the handles and process/title identities of every workspace that stays open, claimed up front - applies in full to a *re-resolved* window, but only its handles apply to an exact handle match. Process name plus title is **not** unique across workspaces: open WinuX and FuturamaSoft and each has a `YouTube - Mozilla Firefox` and a `New chat - Claude - Mozilla Firefox`. Guarding an exact match on identity therefore left the closing workspace's own YouTube and AI windows on screen, protected by the other workspace's identically titled ones.
- **Anything else standing on this workspace's desktops** is closed too, unless a workspace that stays open recorded it or owns the desktop it is on. Identity is deliberately not consulted here either, for the same reason - the desktop already discriminates.
- **Closing** is `WM_CLOSE`, exactly as `Close-Project` does it, so unsaved work still prompts. A window that refuses is reported and left alone - never force-killed.
- **Terminal tabs** are closed through their UI Automation close button (no focus stealing, no synthesized keystrokes), and the window is left to disappear with its last tab, because a `WM_CLOSE` on a multi-tab window raises a "close all tabs?" confirmation. A terminal window the workspace *opened* (the `-Alongside` flow creates one) belongs to it whole, so every tab in it goes; a window it merely put tabs into keeps everything else. Either way an owned window still standing after the tab pass is closed directly, so it can never be orphaned.
- **Terminals on other desktops** are handled by [Ensure-DesktopVisible](window.md#ensure-desktopvisible): Windows Terminal composes its tab strip only while its desktop is visible and reports no tabs at all otherwise, and a workspace's terminal is by definition parked on one of the workspace's own desktops once the layout pass has moved it. The desktop is brought up only when the first read comes back empty, at most once per window, and the view is put back before the desktop sweep.
- **The calling tab**, when it belongs to the workspace being closed, is closed last through `Invoke-TerminateWindowsTerminalTabsExit` - it cannot close itself mid-run. The tracker is written *before* that, because the exit skips everything after it.
- **Afterwards the workspace's desktops go with it** - named explicitly via `Remove-VirtualDesktops -Index`, then `-EmptyOnly` as a net for any desktop this teardown emptied without ever having had a window on it - and focus returns to the calling terminal. Both run last, once everything has actually gone, rather than opening the teardown with a report about desktops the *previous* run emptied.

  Naming them explicitly matters: the one window a teardown cannot close before that point is **the shell it is running in**. When the workspace opened that shell (the `-Alongside` flow does), its desktop is never empty at sweep time, so an `-EmptyOnly` sweep can never remove it and no later run ever would either - the session ends up one desktop wider per open/close cycle. Removing the desktop relocates that window instead of stranding it, which Windows does automatically. Nothing has to be re-mapped afterwards, because no desktop index is ever stored.

Closed entries are dropped from the tracker, so a second call is a clean no-op. There is no confirmation prompt - closing is not destructive and it is the caller's job to know when to run it - but `-WhatIf` gates every close, the tracker write, the desktop removal and the process exit.

### One row per instance

The menu lists one row per tracked **instance**, not per name. Opening the same workspace twice - `w Example -Browser Chrome` then `w Example -Browser Edge -Alongside` - produces two entries describing two separate sets of windows sitting side by side, so either can be closed on its own:

```text
[Open workspaces to close]

 [1] Example (plain, desktop 1)
 [2] Example (alongside, desktop 6)
 [3] WinuX

Enter workspace(s) to close or press [Enter] to cancel (space/comma-separated): 2
```

A name with a single instance keeps its bare name, so the everyday menu gains nothing to read. Several instances of one name are labelled by **where they are**, because that is what the choice is actually between when two of them are on screen at once; the desktop number is 1-based, matching the layout-file convention, and names the desktop the workspace starts on. The teardown title uses the same number, so the two never disagree about which instance is going.

Naming a whole workspace still closes every instance of it, so `Close-Workspace Example` ends that workspace entirely and stays usable from a script - it does not stop to ask. To target one exactly, pick its row or pass the full label as an argument (`Close-Workspace 'Example (alongside, desktop 6)'`). The menu is multi-select, so `1,2` closes both.

One mechanical detail worth knowing: `Resolve-Selection` splits *typed* input on whitespace and commas, so a label containing spaces can only be chosen by its number at the prompt. Passed as an argument it is matched whole, which is why both forms are supported.

| Parameter    | Description                                                                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Workspace` | One or more workspace names to close, or the full label of a single instance. A bare name closes every tracked instance of it. Omit for an interactive menu. Only *tracked* names and labels are offered or accepted - a workspace that is configured but not open is not something this command can close. |
| `-StatePath` | Full path to the tracker file. Defaults to [Get-WorkspaceStatePath](#get-workspacestatepath). Mainly a test seam.                                                    |
| `-WhatIf`    | Report every window, tab and desktop that would be closed, and change nothing.                                                                                      |

```powershell
# Interactive menu listing the workspaces currently open
Close-Workspace

# Close every tracked instance of a workspace, however it was opened
Close-Workspace Server

# Or via the alias
cw Server

# Close ONE instance of a workspace that is open twice, leaving the other running
cw 'Example (alongside, desktop 6)'

# Close two workspaces in one pass
Close-Workspace -Workspace Server, WinuX

# See the whole plan without touching anything
Close-Workspace Server -WhatIf

# Verbose diagnostic output (per-window and per-tab decisions)
Set-LogLevel Verbose { Close-Workspace Server }
```

**See also:** [Open-Workspace](#open-workspace), [Close-Project](#close-project), [Get-WorkspaceState](#get-workspacestate), [Get-WorkspaceOpenDelta](#get-workspaceopendelta), [Wait-WindowsClosed](window.md#wait-windowsclosed), [Ensure-DesktopVisible](window.md#ensure-desktopvisible), [Get-WindowDesktopIndex](window.md#get-windowdesktopindex), [Remove-VirtualDesktops](system.md#remove-virtualdesktops)

## [Docker-Cleanup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Docker-Cleanup.ps1)

- **Description:** Menu-driven Docker maintenance with per-action confirmation safeguards. Presents the actions defined in `Configuration.DockerCleanupActions` (each entry: `Name`, `Command`, optional `ConfirmationMessage`) and runs the selected one. An action carrying a `ConfirmationMessage` only runs after an explicit "Yes" on a red confirmation prompt - pressing Enter defaults to "No" - so destructive operations can never fire on muscle memory.
- **Parameters:** -Action
- **Usage:** `Docker-Cleanup`, `Docker-Cleanup "Delete all volumes"`

The shipped defaults cover the three classic teardown moves - stop all containers, `docker system prune -a --volumes -f`, and delete all volumes - and the list is plain configuration: forks replace it wholesale in `Configuration.local.psd1` to add or reword actions (the override replaces the array, so carry over any defaults you want to keep). The safeguard itself is [Resolve-Selection](helper.md#resolve-selection)'s `-ConfirmationMessage` parameter, so any other caller can reuse it.

| Parameter | Description                                                                                          |
| --------- | ----------------------------------------------------------------------------------------------------- |
| `-Action` | Optional configured action name to run directly, skipping the menu. The confirmation still applies. |

```powershell
# Interactive menu of configured cleanup actions
Docker-Cleanup

# Run a specific action directly - the red confirmation prompt still gates it
Docker-Cleanup "Delete all volumes"
```

**See also:** [DockerWizard](#dockerwizard), [Start-Containers](#start-containers), [Resolve-Selection](helper.md#resolve-selection)

## [DockerWizard](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/DockerWizard.ps1)

- **Description:** Starts or stops Docker Desktop with loading-spinner feedback, daemon readiness detection, graceful Docker Desktop CLI integration, and Docker-owned WSL cleanup. When starting, it can clean up a partial Docker state, launch Docker Desktop in detached mode (falling back to `Open-Docker`), wait for `docker info` to succeed, and optionally start Docker Compose services from an explicit compose file path or a project directory. When stopping, it first requests a graceful shutdown and then force-cleans Docker-owned helper processes and `docker-desktop` WSL distros only if Docker gets stuck. Used by `Run-Project` and `Start-Containers` to transparently spin up database containers.
- **Parameters:** -Stop, -ComposeProjectPath, -ComposeFilePath, -PassThru
- **Usage:** `DockerWizard`, `DockerWizard -Stop`, `DockerWizard -ComposeProjectPath "<DevRoot>\MyProject"`, `DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"`

`DockerWizard` treats Docker Desktop as more than a single Windows process. It also checks for Docker-owned `wsl.exe` helper processes and terminates `docker-desktop` WSL distros when Docker is stuck in a partial `starting` state. On start it polls for daemon readiness; on stop it requests a graceful shutdown and only escalates to force-cleanup if the shutdown stalls. The polling budgets come from `Configuration.DockerTimeouts` (`StartSeconds`/`StopSeconds`/`CleanupSeconds`, defaulting to 180/60/30) so slower machines can raise them.

Compose startup runs `docker compose up -d` unconditionally - `up -d` is idempotent, so a half-stopped stack is reconciled to the compose file instead of being skipped because one container still runs. A compose path that does not exist is reported with a warning instead of being silently ignored.

| Parameter             | Description                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Stop`               | Stops Docker Desktop: requests a graceful shutdown, then force-cleans Docker-owned WSL distros and helper processes if the shutdown stalls. |
| `-ComposeProjectPath` | Project directory to start Compose services from; looks for `docker-compose.yml` or `compose.yml` inside it.                                |
| `-ComposeFilePath`    | Explicit Docker Compose file path; used directly, taking precedence over `-ComposeProjectPath`.                                             |
| `-PassThru`           | Returns `[PSCustomObject]@{ Success; ComposeFilePath }` so callers can branch on the outcome instead of reading module-scoped state.        |

```powershell
# Start Docker Desktop and wait for the daemon to become ready
DockerWizard

# Stop Docker Desktop cleanly
DockerWizard -Stop

# Start Docker and spin up Compose services from a project directory
DockerWizard -ComposeProjectPath "<DevRoot>\MyProject"

# Start Docker and spin up Compose services from a specific compose file
DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"

# Branch on the outcome (what Run-Project and Start-Containers do)
$result = DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml" -PassThru
if (-not $result.Success) { return }
```

**See also:** [Start-Containers](#start-containers), [Docker-Cleanup](#docker-cleanup), [Resolve-ProjectDockerCompose](#resolve-projectdockercompose), [Kill-All](system.md#kill-all)

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
- **Parameters:** -TargetTitle, -WindowHandle, -Quiet
- **Usage:** `Focus-TerminalTab`, `Focus-TerminalTab -TargetTitle "PowerShell"`, `Focus-TerminalTab -WindowHandle $window.Handle -Quiet`

`-WindowHandle` exists because `AppActivate` takes a **process** id and one Windows Terminal process hosts every one of its windows: without it the window that comes forward is that process's main window, not necessarily the wanted one. A caller that has already resolved which terminal window it means - [Focus-VirtualDesktop](window.md#focus-virtualdesktop), which must not let focus wander onto a window living on another virtual desktop - passes the handle, and that exact window is activated through [Confirm-WindowForeground](window.md#confirm-windowforeground) (force and verify, retried while the focus handoff settles), falling back to `SetForegroundWindow` on the same handle. The tab-cycling loop reads its title back from that window too, so it cannot cycle tabs in one window while judging the result by another.

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| `-TargetTitle` | Title of the tab to focus. Omit to only activate the Windows Terminal window without switching tabs. |
| `-WindowHandle` | Activate exactly this terminal window instead of the first `WindowsTerminal` process's main window. |
| `-Quiet`       | Switch. Suppresses the informational output while focusing.                                          |

```powershell
# Activate Windows Terminal without switching tabs
Focus-TerminalTab

# Activate Windows Terminal and cycle to the tab titled "PowerShell"
Focus-TerminalTab -TargetTitle "PowerShell"

# Activate one specific terminal window (the caller owns the section output)
Focus-TerminalTab -WindowHandle $terminalOnTarget.Handle -Quiet
```

## [Format-WorkspaceStateContent](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Format-WorkspaceStateContent.ps1)

- **Description:** Renders open-workspace tracker entries as the PowerShell data file [Get-WorkspaceState](#get-workspacestate) reads back, so the tracker is parsed in restricted language mode (data only, never executed) exactly like the repository's layout and configuration `.psd1` files.
- **Parameters:** -Entry
- **Usage:** `Set-Content -Path $path -Value (Format-WorkspaceStateContent -Entry $entries) -NoNewline`

Deliberately *not* a general-purpose serializer. The tracker schema is fixed and entirely scalar - strings, integers and booleans in a known shape - so each field is written by name with the right conversion. That makes the output predictable, keeps a rogue value from silently changing the file's structure, and avoids a second copy of the recursive serializer `Save-CurrentLayout` carries for its own, differently shaped snapshot. Every string is single-quoted with embedded quotes doubled (the only escaping a PowerShell single-quoted literal needs) because window titles routinely contain apostrophes. An empty array produces a valid file with no entries, which is how a teardown clears the tracker.

| Parameter | Description                                                                              |
| --------- | ---------------------------------------------------------------------------------------- |
| `-Entry`  | The tracker entries to render. Mandatory; may be an empty collection. |

```powershell
# Write the tracker
Set-Content -LiteralPath (Get-WorkspaceStatePath) -Value (Format-WorkspaceStateContent -Entry $entries) -NoNewline -Encoding UTF8
```

**See also:** [Save-WorkspaceState](#save-workspacestate), [Get-WorkspaceState](#get-workspacestate)

## [Get-SwaggerCloseTitlePatterns](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-SwaggerCloseTitlePatterns.ps1)

- **Description:** Returns the Swagger-specific browser tab title patterns to close for a project. Maps the project name to its entry in the `BrowserGroups` `Swagger` group (case-insensitive match on the entry's `Name`) and returns the regex patterns `Close-Project` hands to `Close-BrowserTabsByPattern`. A project with no `Swagger` entry (or a setup with no `Swagger` group at all) returns nothing, so Swagger closing is inert without Swagger configuration.
- **Parameters:** -Project
- **Usage:** `Get-SwaggerCloseTitlePatterns -Project "MyProject"`, `$patterns += @(Get-SwaggerCloseTitlePatterns -Project "MyProject")`

The returned set depends on the entry's URLs: a matched entry always contributes `(?i)swagger ui` (the title the rendered Swagger page carries when the backend is up), and any `localhost`/`127.0.0.1` URL additionally contributes `(?i)problem loading page` (what a failed load renders when the backend is down). This is the Swagger-closing logic that previously lived inline inside `Close-Project`, extracted so that function stays thin and the patterns can be reused. Wrap the call in `@(...)` when appending - an empty result is `AutomationNull`, which would otherwise vanish rather than append nothing.

| Parameter  | Description                                            |
| ---------- | ------------------------------------------------------ |
| `-Project` | Project name to map to a `Swagger` entry. Mandatory.   |

```powershell
# Append a project's Swagger close patterns to an existing pattern list
$patterns = @("(?i)$([regex]::Escape($projectName))")
$patterns += @(Get-SwaggerCloseTitlePatterns -Project $projectName)
```

**See also:** [Close-Project](#close-project), [Close-BrowserTabsByPattern](#close-browsertabsbypattern), [Open-ProjectSwagger](#open-projectswagger)

## [Get-WorkspaceBenchmark](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceBenchmark.ps1)

- **Description:** Reads the workspace benchmark back. [Write-WorkspaceBenchmark](#write-workspacebenchmark) appends one row per workspace open to `WorkspaceBenchmark.csv` (resolved by [Get-WorkspaceBenchmarkPath](#get-workspacebenchmarkpath)); this returns those rows as objects with typed numbers, oldest first: the total, the seconds the launch actions took, the seconds `Set-WorkspaceWindowLayout` spent in each phase (`Preamble`, `Desktops`, `FancyZones`, `Wait`, `Normalize`, `Position`, `Snap`, `Verify`, `Retry`, `Save`), the attempt count and the outcome. This is what a change to the open flow is judged by - run the same workspace a few times before and after, compare the phase columns, and read `Attempts` and `Outcome` first, because a saving that arrives with retries is not a saving. `-Workspace` keeps one or more workspaces, `-Last` bounds the result to the most recent N runs after filtering (10 by default, 0 for all), and `-Summary` aggregates instead: per workspace and mode, the number of runs, average/min/max total, the average of every phase, the retries and the runs that did not end `Applied`. The rows have more columns than PowerShell shows as a table by default, so pipe them to `Format-Table` - or pass `-Formatted`, which renders the standard columns (`Timestamp`, `Attempts`, `Outcome`, `TotalSeconds`, `ActionsSeconds`, `FancyZonesSeconds`, `WaitSeconds`, `PositionSeconds`, `SnapSeconds`) as an auto-sized table, and the summary table when combined with `-Summary`; that is the view [Open-Workspace](#open-workspace) shows at the end of an open when `WorkspaceBenchmark.Display` is `Table`. Warns and returns nothing when no run has been recorded yet.
- **Parameters:** -Workspace, -Last, -Summary, -Formatted, -BenchmarkPath
- **Usage:** `Get-WorkspaceBenchmark -Workspace MyWorkspace -Formatted`, `Get-WorkspaceBenchmark | Format-Table -AutoSize`, `Get-WorkspaceBenchmark -Workspace MyWorkspace -Last 20 | Format-Table Timestamp, Attempts, TotalSeconds, FancyZonesSeconds, WaitSeconds, SnapSeconds`, `Get-WorkspaceBenchmark -Summary -Formatted`

| Parameter        | Description                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `-Workspace`     | One or more workspace names to keep. Omit for every workspace.                                                                          |
| `-Last`          | Number of most recent runs to return, after filtering. `10` by default; `0` for all.                                                    |
| `-Summary`       | Aggregate per workspace and mode instead of returning the raw rows.                                                                     |
| `-Formatted`     | Render a table instead of returning objects: the standard nine columns for rows, every column for `-Summary`, both auto-sized.          |
| `-BenchmarkPath` | Read a different benchmark file. Defaults to `Get-WorkspaceBenchmarkPath`.                                                             |

```powershell
# The last ten opens of one workspace as a table - what Open-Workspace shows after an open
Get-WorkspaceBenchmark -Workspace MyWorkspace -Formatted

# The last ten opens, one row each
Get-WorkspaceBenchmark | Format-Table -AutoSize

# Before/after comparison for one workspace
Get-WorkspaceBenchmark -Workspace MyWorkspace -Last 20 |
    Format-Table Timestamp, Attempts, TotalSeconds, ActionsSeconds, FancyZonesSeconds, WaitSeconds, PositionSeconds, SnapSeconds

# Averages per workspace and mode
Get-WorkspaceBenchmark -Summary | Format-Table -AutoSize
```

**See also:** [Write-WorkspaceBenchmark](#write-workspacebenchmark), [Get-WorkspaceBenchmarkPath](#get-workspacebenchmarkpath), [Get-WorkspaceLayoutTimings](window.md#get-workspacelayouttimings), [Open-Workspace](#open-workspace)

## [Get-WorkspaceBenchmarkPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceBenchmarkPath.ps1)

- **Description:** Resolves the path of the workspace benchmark file - `WorkspaceBenchmark.csv` in the Logging module's `Logs` folder (`Get-LogPath -Directory`, which honours the `Logging.FileLogging.Directory` override) - so [Write-WorkspaceBenchmark](#write-workspacebenchmark) and [Get-WorkspaceBenchmark](#get-workspacebenchmark) can never disagree about where the rows live. Falls back to the Workflow module's `State` folder, beside the open-workspace tracker, when the Logging module is not loaded. Both locations are git-ignored: the rows are per-machine measurements with no meaning anywhere else. The file may not exist yet; nothing here creates it.
- **Usage:** `Get-WorkspaceBenchmarkPath`, `Import-Csv (Get-WorkspaceBenchmarkPath)`

**See also:** [Get-WorkspaceBenchmark](#get-workspacebenchmark), [Write-WorkspaceBenchmark](#write-workspacebenchmark), [Get-WorkspaceStatePath](#get-workspacestatepath), [Get-LogPath](logging.md#get-logpath)

## [Get-WorkspaceOpenDelta](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceOpenDelta.ps1)

- **Description:** The ownership rule for [Close-Workspace](#close-workspace), in one place. Given the window handles and the Windows Terminal tab snapshot taken *before* an `Open-Workspace` invocation ran its actions, this enumerates what exists now and returns the difference as a single tracker entry.
- **Parameters:** -Workspace, -ExistingWindowHandles, -ExistingTerminalTabs, -PreCapturedTerminalTabs, -DesktopOffset, -Alongside, -AdoptUnclaimed, -ProtectedWindowHandles
- **Usage:** `Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore`

**Windows** are differenced by handle. Anything on screen whose handle was not there before belongs to this open; anything that was already there does not - which is exactly what keeps a single-instance application out of a later workspace's entry. Both process id and window title are recorded alongside the handle, because handles are the only unambiguous key while a window lives but Electron applications recreate their window (new handle, same process) and a restarted application keeps neither; the extra fields let `Close-Workspace` re-resolve a record whose handle has gone stale.

Which virtual desktops the workspace occupies is deliberately **not** recorded. Desktop indexes shift whenever a desktop to their left is removed, so a stored index goes stale and acting on a stale one would reach onto another workspace's desktop; `Close-Workspace` derives the set live from where the entry's windows actually are instead.

**Terminal tabs** cannot be differenced by handle - they are not top-level windows - so they are differenced per Windows Terminal window by title, and **by count rather than by set membership**. A second tab titled `MyProject.Api` opened next to an existing one is a new tab even though the title was already present; set subtraction would miss it and leave it running. The current tab strip normally arrives ready-made in `-PreCapturedTerminalTabs`: `Open-Workspace` takes that snapshot while the terminal is still on the visible desktop, right before its layout action parks it on one of the workspace's own desktops. Reading it *here* is the expensive path, because this runs at the **end** of an open and Windows Terminal exposes no tab strip while its desktop is off screen - so the fallback read uses [Get-TerminalTabSnapshot](helper.md#get-terminaltabsnapshot) `-EnsureVisible` and pays a desktop round trip, which the user sees as the view jumping to the terminal and back *after* the workspace's final [Focus-VirtualDesktop](window.md#focus-virtualdesktop) landing. A supplied but **empty** map is honoured rather than re-read: it means the caller looked and found no readable terminal.

`-AdoptUnclaimed` also claims what was already on screen, which is what makes an already-running application closable at all (see [Close-Workspace](#close-workspace) for why that matters). Adoption reaches only for what `Universal.VisibleWindowExclusions` does not name, and it never overrides the diff: a window this open genuinely created is always recorded. Use it for the **first** workspace of a plain run only - never for `-Alongside`, which would steal another workspace's windows, and never twice in one run, because both entries would then claim the same windows and each would protect them from the other's teardown. `-ProtectedWindowHandles` bounds adoption once more: the handles of alongside workspaces a plain open preserves (from [Get-WorkspaceOpenProtection](#get-workspaceopenprotection)) are never adopted - neither the windows nor, for a protected terminal window, its tabs - or closing this workspace would take the preserved one's windows down with it.

Returns one ordered entry: `Workspace`, `Alongside`, `DesktopOffset`, `OpenedUtc` (round-trippable `o` format), `ShellPid`, `Windows`, `TerminalTabs`.

| Parameter                | Type      | Default | Description                                                                                                          |
| ------------------------ | --------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `-Workspace`             | string    | -       | Name of the workspace this entry belongs to. Mandatory.                                                               |
| `-ExistingWindowHandles` | object    | -       | Handles that existed before the open. Accepts a `HashSet[IntPtr]`, raw handle values, or window objects exposing `.Handle`. |
| `-ExistingTerminalTabs`  | hashtable | -       | The pre-open `Get-TerminalTabSnapshot` (window handle -> tab titles). Omit and every tab on screen counts as new.       |
| `-PreCapturedTerminalTabs` | hashtable | -     | The matching **after** snapshot, taken by the caller while the terminal was still on screen. Supply it and no tab strip is read here (and no desktop is switched); omit it for the `-EnsureVisible` read. |
| `-DesktopOffset`         | int       | `0`     | Desktop offset the open used (`0` normally, `+N` for `-Alongside`). Recorded for context.                              |
| `-Alongside`             | switch    | off     | Records that the workspace was opened alongside existing desktops.                                                     |
| `-AdoptUnclaimed`        | switch    | off     | Also claim what was already on screen, minus `Universal.VisibleWindowExclusions`. First workspace of a plain run only.  |
| `-ProtectedWindowHandles` | object   | -       | Live handles of preserved alongside workspaces (same accepted shapes as `-ExistingWindowHandles`). Adoption never claims them, tabs included; diff-created windows are always recorded regardless. |

```powershell
# What did this open actually produce?
$entry = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore
"$(@($entry.Windows).Count) window(s), $(@($entry.TerminalTabs).Count) tab(s)"
```

**See also:** [Save-WorkspaceState](#save-workspacestate), [Close-Workspace](#close-workspace), [Get-WorkspaceOpenProtection](#get-workspaceopenprotection), [Get-TerminalTabSnapshot](helper.md#get-terminaltabsnapshot)

## [Get-WorkspaceOpenProtection](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceOpenProtection.ps1)

- **Description:** Resolves what a plain workspace open must leave alone: tracked `-Alongside` workspaces that still have at least one live window. Returns their tracker entries verbatim plus a `HashSet[IntPtr]` of the live window handles they own, or `$null` when there is nothing to preserve. This is what makes a plain rerun of workspace A stop destroying a workspace B that is open alongside it.
- **Parameters:** -StatePath
- **Usage:** `Get-WorkspaceOpenProtection`, `Get-WorkspaceOpenProtection -StatePath $trackerPath`

Without protection a plain rerun destroyed a live alongside workspace three ways at once: the virtual-desktop resize shrank the count back to the plain layout's requirement and removed exactly the alongside desktops (with their FancyZones grids), the plain layout pass matched and moved the alongside windows (layout entries match by process/title, and `Browser` matches any browser window), and the plain tracker/CurrentLayout writes replaced both files wholesale - wiping the alongside entry (making it unclosable) and its zone-pinning section.

The protection set is derived the same way [Close-Workspace](#close-workspace) derives what a teardown must spare: from the tracker [Save-WorkspaceState](#save-workspacestate) wrote, never from configuration. Every tracked entry with `Alongside = $true` is checked against the live windows; an entry with at least one live window is **preserved** - its tracker entry travels forward verbatim (dead records included, the same staleness `Close-Workspace` tolerates) and its resolved handles become untouchable for the whole open. Records are resolved with `Close-Workspace`'s exact ladder: live handle first, then same `ProcessId` + `ProcessName` (Electron applications recreate their window without restarting), then same `ProcessName` + exact `Title` (the application restarted outright) - the third step sharing that function's accepted false-positive risk, since two workspaces routinely hold identically titled windows. Plain entries are never preserved: a plain rerun replaces the plain session by design. The common case - no alongside workspace tracked - pays one file parse and short-circuits to `$null` before any window enumeration.

Consumed by [Open-Workspace](#open-workspace), which resolves it once per plain run (before any action can spawn a process) and threads the handle set to every action that declares `-ProtectedWindowHandles` and the entries into the tracker write. [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout) also self-derives the set on a standalone plain call when this function is available.

| Parameter    | Description                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------- |
| `-StatePath` | Full path to the tracker file. Defaults to [Get-WorkspaceStatePath](#get-workspacestatepath). Mainly a test seam. |

```powershell
# What would a plain open preserve right now?
$protection = Get-WorkspaceOpenProtection
if ($protection) {
    "preserving $(@($protection.Entries).Count) alongside workspace(s), $($protection.WindowHandles.Count) window(s)"
}
```

**See also:** [Open-Workspace](#open-workspace), [Close-Workspace](#close-workspace), [Save-WorkspaceState](#save-workspacestate), [Get-WorkspaceOpenDelta](#get-workspaceopendelta), [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout)

## [Get-WorkspaceState](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceState.ps1)

- **Description:** Reads the open-workspace tracker written by [Save-WorkspaceState](#save-workspacestate), parsing it with the same `Import-PowerShellDataFile` used for layout and configuration `.psd1` files. This tracker is the **only** input to a [Close-Workspace](#close-workspace) teardown.
- **Parameters:** -Workspace, -StatePath
- **Usage:** `Get-WorkspaceState`, `Get-WorkspaceState -Workspace Server`

Each entry describes one `Open-Workspace` invocation. A plain open replaces the file (it resets the virtual desktops, so nothing earlier survives it); every `-Alongside` open appends, so the same workspace name can legitimately appear more than once - those are separate instances with separate windows, and entries keep their recorded order so the oldest open for a name comes first.

Reading never throws. A missing file returns `$null`, and so does an unparseable one, so callers can treat "no tracker" as a single case. A file that parses but holds no entries returns an object with an **empty** `Entries` array instead: "the tracker exists and nothing is open" is a different answer from "there is no tracker", and `Close-Workspace` reports them differently. Returns a `PSCustomObject` with `Path` and `Entries`.

| Parameter    | Description                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| `-Workspace` | Optional. Return only the entries for these workspace names (case-insensitive).                                     |
| `-StatePath` | Full path to the state file. Defaults to [Get-WorkspaceStatePath](#get-workspacestatepath).                          |

```powershell
# Is anything tracked as open?
$state = Get-WorkspaceState
if (-not $state) { "nothing has been opened since the tracker was last cleared" }
elseif (@($state.Entries).Count -eq 0) { "the tracker exists, but nothing is open" }

# Every tracked instance of one workspace, oldest first
(Get-WorkspaceState -Workspace Server).Entries | Format-Table Workspace, Alongside, DesktopOffset, OpenedUtc
```

**See also:** [Save-WorkspaceState](#save-workspacestate), [Get-WorkspaceStatePath](#get-workspacestatepath), [Close-Workspace](#close-workspace)

## [Get-WorkspaceStatePath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Get-WorkspaceStatePath.ps1)

- **Description:** Resolves the path of the open-workspace tracker file - `Workflow\State\OpenWorkspaces.txt` inside the repository this function was loaded from - so neither the writer nor the reader has to know the folder depth and the two can never disagree. Resolved through `Get-RepositoryPath` rather than by counting parent folders.
- **Parameters:** -StartPath
- **Usage:** `Get-WorkspaceStatePath`, `Get-Content (Get-WorkspaceStatePath)`

The `State` folder is git-ignored with a `.gitkeep`, following `Logging\Logs` and `Window\Layouts\CurrentLayout.txt`: it is per-machine runtime state describing which windows are open *right now*, which is meaningless on any other machine and in any later session. Deleting the file is safe - `Close-Workspace` then reports that nothing is tracked rather than guessing. Like `Save-CurrentLayout`'s snapshot the file is named `.txt`, not `.psd1`, even though its contents are a PowerShell data file: nothing should mistake per-machine runtime state for a module manifest or a configuration file that belongs under version control. The file itself may not exist yet.

| Parameter     | Description                                                                                                    |
| ------------- | -------------------------------------------------------------------------------------------------------------- |
| `-StartPath`  | Directory to anchor the repository search on. Defaults to this function's own location.                         |

```powershell
# Show the raw tracker contents
Get-Content (Get-WorkspaceStatePath)
```

**See also:** [Get-WorkspaceState](#get-workspacestate), [Save-WorkspaceState](#save-workspacestate), [Get-RepositoryPath](helper.md#get-repositorypath)

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
- **Parameters:** -Project, -RunApp, -VSCodeWorkspace, -InSameShell
- **Usage:** `Open-Project`, `Open-Project MyProject`, `Open-Project MyProject -RunApp`
- **Projects:** MyProject, OtherProject (the entries of the `Projects` array in `Configuration.psd1`)

Each action in `ProjectActions` is a named PowerShell function (e.g. `Open-VSCode`, `Open-VisualStudio`, `Open-Browser`) whose parameters are resolved at runtime. The `{ProjectName}` placeholder in any action parameter is replaced with the actual project name at execution time. When no project name is supplied, an interactive menu lists every project in the `Projects` array; multiple projects may be selected and each is opened in sequence. The special action `Open-ProjectTerminals-Or-RunProject` is context-sensitive: with `-RunApp` it starts the server via `Run-Project`, otherwise it opens terminal tabs via `Open-ProjectTerminals`. When `-VSCodeWorkspace <name>` is set, the project's `Open-VSCode` action opens the given `.code-workspace` (via `Open-VSCodeWorkspace`) in place of the project folder. An explicitly passed `-InSameShell` overrides the configured value of the `Open-ProjectTerminals-Or-RunProject` action - `Open-Workspace`'s `-Alongside` relaunch uses this to gather the project's terminal tabs in the relaunched shell window. The function returns the list of project names that were opened.

| Parameter          | Description                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Project`         | One or more project names from the `Projects` configuration array. Omit to show the interactive selection menu.                            |
| `-RunApp`          | Starts the project's runnable app instead of opening terminals (applies to the `Open-ProjectTerminals-Or-RunProject` action only).         |
| `-VSCodeWorkspace` | When set, the project's `Open-VSCode` action opens the given `.code-workspace` (via `Open-VSCodeWorkspace`) instead of the project folder. |
| `-InSameShell`     | When explicitly passed, overrides the configured `InSameShell` of the `Open-ProjectTerminals-Or-RunProject` action so terminal tabs open in the caller's window. |

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

## [Open-ProjectSwagger](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-ProjectSwagger.ps1)

- **Description:** Opens a project's Swagger UI tab, if it has one and it is not already open. This is the **opt-in workspace action** for per-project Swagger tabs: it resolves the project's entry in the `BrowserGroups` `Swagger` group via [Resolve-SwaggerBrowserGroup](#resolve-swaggerbrowsergroup) (which also runs the probe-driven already-open check) and hands the resolved group to `Open-Browser`. It no-ops silently when no project is supplied, when the project has no `Swagger` entry, or when the tab is already open - so a workspace can declare it unconditionally and a setup with no Swagger configuration never does anything.
- **Parameters:** -Project, -Browser
- **Usage:** `Open-ProjectSwagger -Project "MyProject"`, `Open-ProjectSwagger -Project $selectedProjects -Browser "Firefox"`

Declare it in `WorkspaceActions` **after** the workspace's `Open-Project` and `Open-Browser` actions, using the [`{SelectedProjects}`](#open-workspace) token to supply the project context:

```powershell
WorkspaceActions = @{
    MyWorkspace = @(
        @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub") } }
        @{ Action = "Open-ProjectSwagger"; Parameters = @{ Project = "{SelectedProjects}" } }
    )
}
```

Swagger used to be wired into `Open-Workspace` itself, which auto-added the group to every `Open-Browser` action for every user. It is now entirely declarative: no action in a workspace means no Swagger code runs for that workspace. `-Project` is deliberately optional rather than mandatory - when `{SelectedProjects}` resolves to nothing, `Open-Workspace` drops the parameter, and this function must then no-op rather than fail the action. The end state is unchanged from the old inline behaviour: a single-URL group launches with the browser's new-window argument exactly as it did when appended to the workspace's own `Open-Browser` call.

| Parameter   | Default                    | Description                                                                                       |
| ----------- | -------------------------- | ------------------------------------------------------------------------------------------------- |
| `-Project`  | -                          | Project name(s) to open the Swagger tab for; the first non-empty element is used. Optional by design (see above). |
| `-Browser`  | `Universal.DefaultBrowser` | Browser to open the tab in.                                                                       |

```powershell
# Open one project's Swagger tab by hand (respects the already-open check)
Open-ProjectSwagger -Project "MyProject"

# Verbose diagnostic output, including the backend probe result
Set-LogLevel Verbose { Open-ProjectSwagger -Project "MyProject" }
```

**See also:** [Resolve-SwaggerBrowserGroup](#resolve-swaggerbrowsergroup), [Open-Workspace](#open-workspace), [Open-Browser](application.md#open-browser), [Test-TcpPortReachable](helper.md#test-tcpportreachable)

## [Open-ProjectTerminals](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Open-ProjectTerminals.ps1)

- **Description:** Opens project-specific Windows Terminal tabs based on `Configuration.ProjectTerminals`, with automatic tab naming (`ProjectName.PathKey`, e.g. `MyProject.Api`, `WinuX.Root`), optional onefetch repository info, and flexible focus control. Smart idempotency checks all Windows Terminal windows: if every expected tab already exists it warns and skips (unless `-Force`), and if only some exist it opens just the missing ones in the current window. Window grouping is controlled by `-InSameShell` and `-InSameGroup`, and when `-InSameShell` is omitted the function auto-detects whether to reuse the single open window or start a new one to keep project groups separate.
- **Parameters:** -Project, -InvokeOnefetch, -InSameShell, -InSameGroup, -FocusTab, -Force
- **Usage:** `Open-ProjectTerminals`, `Open-ProjectTerminals -Project "MyProject"`, `Open-ProjectTerminals -Project "MyProject", "OtherProject" -InSameShell`, `Open-ProjectTerminals -Project "MyProject" -FocusTab "origin"`, `Open-ProjectTerminals -Project "MyProject" -FocusTab "MyProject.Api"`, `Open-ProjectTerminals -Project "MyProject", "OtherProject" -InvokeOnefetch:$false`, `Open-ProjectTerminals -Project "MyProject" -Force`
- **Projects:** Defined in `Configuration.ProjectTerminals` (e.g. `MyProject`, `OtherProject`)
- **FocusTab Options:** `"origin"` returns to the original tab where the function was called, `"ProjectName.PathKey"` focuses a specific project tab (e.g. `MyProject.Api`), numeric index focuses the tab at that position (e.g. `"0"` for the first tab)

Reads project definitions from `ProjectTerminals` in `Configuration.psd1`. Each project lists one or more `Paths`; every path opens in its own tab named `ProjectName.PathKey`. Regular path keys resolve through `PathTemplates` via `Resolve-ProjectPath`, while special entries cover shells and explicit locations. When `InvokeOnefetch` is on, each resolved-path tab runs `onefetch` after `Set-Location`. Consecutive `pwsh` tabs of one project are queued and flushed as one batched `Open-Terminal` call - a single ordered `wt` invocation - while WSL tabs (which use a different Windows Terminal profile) flush the queue first so the on-screen tab order matches the configured order; without a shared project window, each tab still gets its own window GUID. Named-tab focusing navigates with `Ctrl+Shift+Tab` relative to the last created tab, so it applies only when tabs share a window.

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

- **Description:** The main entry point for starting work. Opens a predefined workspace by executing a configured sequence of actions (projects, browser tab groups, applications, and window layouts) across virtual desktops. Use `-Alongside` to spawn the workspace on new virtual desktops to the right of existing ones, letting multiple workspaces run simultaneously without interfering. An `-Alongside` invocation always runs in a completely new shell: it relaunches itself in a fresh Windows Terminal window (the calling shell gets its prompt back immediately) and, inside that window, forces `-InSameShell` on terminal-opening actions so the workspace's terminal tabs join the new window instead of spawning further windows. In alongside mode the computed desktop offset is injected into the workspace's actions so they land on the new desktops - both `Set-WorkspaceWindowLayout` and the final `Focus-VirtualDesktop` action receive `-DesktopOffset`, so the configured landing (e.g. `DesktopNumber = 1`) focuses the new workspace's own first desktop instead of the original desktop 1. Automatically reconciles the calling terminal tab via `Terminate-WindowsTerminalTabs -OnlyCurrent` (skipped when re-running from a same-workspace project tab; in alongside mode it runs inside the relaunched window and closes that window's now-redundant bootstrap tab). When the flow ends - success or failure - it releases any logically stuck keyboard modifiers via `Reset-KeyboardModifiers` (Window module), so orchestration can never leave the session with the stuck-modifier input lockup. Diagnostic output for the workspace and its actions is shown when run under `Set-LogLevel Verbose`. With `Configuration.WorkspaceBenchmark.Enabled` set (off in the base), every workspace it opens is measured: each action is timed, the layout phase clock is read back through [Get-WorkspaceLayoutTimings](window.md#get-workspacelayouttimings), [Write-WorkspaceBenchmark](#write-workspacebenchmark) appends the row to `WorkspaceBenchmark.csv`, and the end of the open shows either the workspace's recent runs as a table (`Display = "Table"`, `Last` rows, rendered through [Get-WorkspaceBenchmark](#get-workspacebenchmark) `-Formatted`), one `Timing =>` line (`"Line"`), or nothing beyond the row (`"None"`).
- **Parameters:** -Workspace, -Project, -Alongside, -VSCodeWorkspace
- **Usage:** `Open-Workspace`, `Open-Workspace MyWorkspace`, `Open-Workspace MyWorkspace MyProject`, `Open-Workspace MyWorkspace -Alongside`, `w dotfiles -VSCodeWorkspace Consolidation`, `w MyWorkspace`
- **Alias:** w

Reads the workspace list from `Configuration.Workspaces` and the per-workspace action sequence from `Configuration.WorkspaceActions`. With no argument it shows an interactive menu (multiple selections allowed); pressing Enter there opens the workspace named by `Configuration.DefaultWorkspace` (`Default` out of the box), which the prompt names explicitly. The default is only offered when it has a `WorkspaceActions` entry - set `DefaultWorkspace = ""` (or point it at a workspace with no actions) and the prompt reads `press [Enter] to cancel` instead, with Enter exiting without opening anything. The fallback covers the interactive Enter only: a mistyped `-Workspace` argument resolves to nothing and exits rather than silently opening the default. A typical workspace opens browser tab groups, the Obsidian vault, the project (Visual Studio, VS Code, terminals), DBeaver, communication apps, and finally applies the window layout. Actions can receive the workspace's project context through the **`{SelectedProjects}` token**: a configured parameter whose FULL value is the literal string `"{SelectedProjects}"` resolves at runtime to the explicit `-Project` argument, otherwise to the projects returned by this workspace's `Open-Project` action; when neither exists the parameter is dropped so the consuming action can no-op or apply its own default. Declare token consumers - [Open-ProjectSwagger](#open-projectswagger) being the one that ships - AFTER the `Open-Project` action. Any extra `-Name Value` / `-Switch` arguments are forwarded to the underlying actions, with the workspace configuration taking precedence. Passing `-VSCodeWorkspace <name>` (or a bare `-VSCodeWorkspace` for a selection menu, or a `DefaultVSCodeWorkspaces` config entry for the workspace) opens `<name>.code-workspace` in place of the project folder - the resolved name (precedence: command-line value, then the bare-switch menu, then the config default) is passed to the `Open-Project` action, which reroutes `Open-VSCode` to `Open-VSCodeWorkspace`. The window layout needs no coupling to this: VS Code layout entries match by process, so the workspace window lands in the VS Code slot like any other VS Code window.

Everything the flow spawns inherits the invoking shell's token, so running from an **elevated** shell produces elevated app windows (and, if PowerToys is not yet running, an elevated PowerToys) that a non-elevated FancyZones cannot snap. The function logs a warning when it detects an elevated shell and proceeds unchanged - prefer running workspaces from a normal shell.

**Every open records what it produced, so it can be closed again.** Before the actions run, the flow captures the window handles on screen (it already did, for the layout pass) plus the Windows Terminal tab strip via [Get-TerminalTabSnapshot](helper.md#get-terminaltabsnapshot) - tabs are not top-level windows, so a handle diff cannot see them. The matching **after** snapshot is taken during the run rather than at the end: right before the `Set-WorkspaceWindowLayout` action, which is what parks the terminal on one of the workspace's own desktops, and Windows Terminal shows no tab strip while its desktop is off screen. Reading it afterwards would cost a desktop round trip the user sees as the view jumping to the terminal and back *after* the workspace's final `Focus-VirtualDesktop` landing. When the actions finish it hands all of it to [Save-WorkspaceState](#save-workspacestate), which stores the difference as one tracker entry per workspace and is what makes [Close-Workspace](#close-workspace) possible. The record is written *before* a terminating `Terminate-WindowsTerminalTabs -OnlyCurrent`/`-IncludeCurrent` action, for the same reason the elapsed summary is: that action ends the process outright. Only the first workspace of a plain run claims what was already on screen (`-AdoptUnclaimed`); later ones append to the session it defined, and an `-Alongside` open never claims, so it cannot take another workspace's windows. Writing the tracker is best-effort - a failure warns and the open continues.

**A plain open resets only what it owns.** Before any action runs, a plain (non-`-Alongside`) open calls [Get-WorkspaceOpenProtection](#get-workspaceopenprotection): tracked `-Alongside` workspaces that still have at least one live window are **preserved**. Their window handles are forwarded as `-ProtectedWindowHandles` to every action that declares the parameter (the same `Get-FilteredParams` mechanism as `-Alongside`), so the layout pass never moves or counts them, count-based openers such as `Open-Browser -Instances` never count them, and the desktop resize never shrinks below them; their tracker entries seed the tracker write (`Save-WorkspaceState -PreserveEntry`) and their `CurrentLayout.txt` sections survive the plain snapshot write. Rerunning `w A` with workspace B open alongside therefore resets A without destroying B. Alongside opens already add without destroying and resolve no protection of their own.

Once the workspace names are resolved (including interactive menu picks), the exact invocation - resolved workspace names, `-Project`, `-Alongside`, and any extra arguments - is recorded in-process through [Set-WorkspaceRerunCommand](window.md#set-workspacereruncommand) (cleared in the `finally` block and before a terminating action exits), so a failure-path respawn via `Set-WorkspaceWindowLayout`'s escalation to `ReRun-LastCommand` reruns precisely this command instead of scraping the shared PSReadLine history. Neither that record nor the elapsed-time base is a process environment variable any more: both used to be, and every application and terminal tab the open spawned inherited them, so a later `Open-Workspace` typed into such a tab reported the time since the earlier open (597 s and 704 s showed up in the session logs) and a standalone layout escalation there would have respawned the inherited open. The one legitimate hand-over remains: the alongside bootstrap command sets `OPEN_WORKSPACE_START_UTC` for the relaunched shell so its summary includes the relaunch, and that shell consumes it at entry, before anything it spawns could inherit it. In alongside mode, when `Get-NextAvailableDesktopIndex` cannot determine the next free desktop (virtual desktop enumeration failed), that workspace is skipped with a clear error instead of opening on top of the current one. And because a configured `Terminate-WindowsTerminalTabs` action with `-OnlyCurrent` or `-IncludeCurrent` ends the process via `[Environment]::Exit` - which skips `finally` blocks - the elapsed summary is printed and stuck keyboard modifiers are released before control passes to that action.

| Parameter          | Description                                                                                                                                                                                                                                                                         |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Workspace`       | One or more workspace names to open. Omit to show the selection menu, where Enter opens `Configuration.DefaultWorkspace` (or cancels, when no usable default is configured).                                                                                                         |
| `-Project`         | Optional project name(s) forwarded to the `Open-Project` action within the workspace.                                                                                                                                                                                               |
| `-Alongside`       | Opens the workspace on new virtual desktop(s) added to the right of existing ones, so multiple workspaces coexist. Always relaunches in a new Windows Terminal window; the workspace's terminal tabs open in that window (`-InSameShell` is forced on terminal-opening actions). Forwarded to every action that declares the parameter - see below.     |

**Alongside is forwarded to the actions, not just to the layout.** Alongside changes *what* an action may work with, not only where its windows land: the layout pass positions solely the windows this open created and refuses every handle captured beforehand. A count-based opener therefore has to know. `Open-Workspace` sets `-Alongside` on each action's parameters and lets `Get-FilteredParams` drop it from the ones that do not declare it, so [`Open-Browser -Instances N`](../modules/application.md#open-browser) switches from "ensure N windows exist" to "open N **new** windows". Without it, a workspace such as `Example` (33 identical `Browser` layout entries) opened alongside was starved by exactly the number of browser windows that happened to be open, and got worse on every rerun.
| `-VSCodeWorkspace` | Opens `<name>.code-workspace` (from `VSCode\Workspaces`) in place of the project folder. Pass a bare `-VSCodeWorkspace` for a selection menu; omit it to use the `DefaultVSCodeWorkspaces` config entry (if any) or normal folder behaviour. |

```powershell
# Interactive workspace selection menu (Enter = Configuration.DefaultWorkspace)
Open-Workspace

# Open a specific workspace by name
Open-Workspace MyWorkspace

# Open a workspace and select the project to open within it
Open-Workspace MyWorkspace MyProject

# Open another workspace on new desktops alongside the current one
# (relaunches in a new shell window; its terminal tabs open in that window)
Open-Workspace OtherProject -Alongside

# Open a workspace but load a .code-workspace file instead of the project folder
w dotfiles -VSCodeWorkspace Consolidation

# Verbose diagnostic output
Set-LogLevel Verbose { w MyWorkspace }
```

**See also:** [Open-Project](workflow.md#open-project), [Close-Project](workflow.md#close-project), [Close-Workspace](#close-workspace), [Open-Browser](../modules/application.md), [Open-ProjectSwagger](#open-projectswagger), [Save-WorkspaceState](#save-workspacestate)

## [Resolve-ProjectDockerCompose](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Resolve-ProjectDockerCompose.ps1)

- **Description:** The single place that knows which Docker Compose source a runnable project's database containers come from. Looks up the project's `RunnableProjectMappings` entry, resolves the database provider (prompting via `Resolve-Selection` when several are configured), and decides whether Docker is required: the mapping sets `UsesDocker`, or the provider maps to a centralized compose file in `Configuration.DockerComposeFiles`, or the provider is Oracle (project-local compose file). Returns `$null` when the project needs no Docker.
- **Parameters:** -ProjectName, -DatabaseProvider
- **Usage:** `Resolve-ProjectDockerCompose -ProjectName "MyProject"`, `Resolve-ProjectDockerCompose -ProjectName "MyProject" -DatabaseProvider "PostgreSQL"`

Extracted from `Run-Project`, which used to inline this resolution between its project menu and its terminal-tab logic. `Run-Project` calls it behind its optional Docker step (see [Resolve-RunProjectSteps](helper.md#resolve-runprojectsteps)); `Start-Containers` does not need it - it works directly on the `DockerComposeFiles` entries.

The result carries the resolved provider and exactly one of the two compose shapes `DockerWizard` accepts:

```powershell
[PSCustomObject]@{
    Provider           = "PostgreSQL"
    ComposeFilePath    = "<RepoRoot>\Docker\docker-compose.postgresql.yml"  # centralized compose file
    ComposeProjectPath = $null                                              # or the project root (project-local branch)
}
```

| Parameter           | Description                                                                          |
| ------------------- | -------------------------------------------------------------------------------------- |
| `-ProjectName`      | Name of the runnable project to resolve (a `RunnableProjectMappings` entry). Mandatory. |
| `-DatabaseProvider` | Optional provider to use; skips the provider menu when given.                          |

```powershell
# Resolve a project's compose source (may prompt for the provider)
Resolve-ProjectDockerCompose -ProjectName "MyProject"

# Resolve non-interactively for a known provider
Resolve-ProjectDockerCompose -ProjectName "MyProject" -DatabaseProvider "PostgreSQL"
```

**See also:** [Start-Containers](#start-containers), [DockerWizard](#dockerwizard), [Run-Project](helper.md#run-project)

## [Resolve-SwaggerBrowserGroup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Resolve-SwaggerBrowserGroup.ps1)

- **Description:** Resolves the `Swagger` browser group for a project so it can be handed to `Open-Browser`. Maps a project name to its entry in the `BrowserGroups` `Swagger` group (case-insensitive match on the entry's `Name`) and returns that group name. By default it also checks whether the project's Swagger tab is already open and returns `$null` when it is, so callers never open a duplicate. That check is **probe-driven**: a short TCP connect to the Swagger URL's host and port ([Test-TcpPortReachable](helper.md#test-tcpportreachable)) decides its mode. Returns `$null` when the project has no `Swagger` entry, no project name is supplied, or the tab is already open. Called by [Open-ProjectSwagger](#open-projectswagger), the opt-in workspace action.
- **Parameters:** -Project, -Browser, -CachedBrowserWindows, -SkipDuplicateCheck
- **Usage:** `Resolve-SwaggerBrowserGroup -Project "MyProject"`, `Resolve-SwaggerBrowserGroup -Project $selectedProjects -Browser "Firefox"`, `Resolve-SwaggerBrowserGroup -Project "MyProject" -SkipDuplicateCheck`

The two probe outcomes:

- **Backend up** - strict title matching via `Test-BrowserGroupAlreadyOpen`, which requires a failed-load window to carry host/port evidence before it counts as this group. A stale error tab from another project therefore cannot suppress a live Swagger tab.
- **Backend down** - the strict check still runs first (it catches a stale but still-loaded "Swagger UI" tab whose backend has since died), and then **any** window matching `BrowserGroupMatching.Matching.ProblemLoadingPagePattern` counts as the tab being open. A failed load renders a generic title - Firefox's bare "Problem loading page" names no host or port - so the strict check can never claim it, and without this every re-run of the workspace stacked another error tab. With no failed-load window present the group is still returned, so a first open (including a deliberate problem-page placeholder that reserves a window-layout zone) behaves exactly as before.

`-Project` accepts an array and uses the first non-empty element. `-Browser` defaults to `Universal.DefaultBrowser`. `-CachedBrowserWindows` forwards a pre-fetched window list to both the duplicate check and the failed-load scan, so neither re-enumerates windows. `-SkipDuplicateCheck` returns the resolved group name without the already-open check **or the probe** (the pure config lookup). A Swagger lookup failure is logged and treated as "no group", so it never aborts the workspace.

| Parameter               | Default                    | Description                                                                                        |
| ----------------------- | -------------------------- | -------------------------------------------------------------------------------------------------- |
| `-Project`              | -                          | Project name to map; an array is accepted and the first non-empty element is used. Mandatory.      |
| `-Browser`              | `Universal.DefaultBrowser` | Browser used for the already-open check.                                                           |
| `-CachedBrowserWindows` | -                          | Pre-fetched window handle list reused by `Test-BrowserGroupAlreadyOpen` and the failed-load scan.  |
| `-SkipDuplicateCheck`   | `$false`                   | Returns the resolved group name without the already-open check or the backend probe (pure config lookup). |

```powershell
# Resolve a project's Swagger group (or $null if it has none / is already open)
$group = Resolve-SwaggerBrowserGroup -Project "MyProject"
if ($group) { Open-Browser $group }

# Pure config lookup, skipping the window/duplicate check
Resolve-SwaggerBrowserGroup -Project "MyProject" -SkipDuplicateCheck
```

**See also:** [Open-ProjectSwagger](#open-projectswagger), [Open-Workspace](#open-workspace), [Open-Browser](application.md#open-browser), [Test-BrowserGroupAlreadyOpen](application.md#test-browsergroupalreadyopen), [Test-TcpPortReachable](helper.md#test-tcpportreachable)

## [Save-WorkspaceState](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Save-WorkspaceState.ps1)

- **Description:** Records what an `Open-Workspace` invocation actually opened, so [Close-Workspace](#close-workspace) can close it. Called once per workspace after its actions have run; delegates the before/after diff to [Get-WorkspaceOpenDelta](#get-workspaceopendelta) and the file format to [Format-WorkspaceStateContent](#format-workspacestatecontent).
- **Parameters:** -Workspace, -ExistingWindowHandles, -ExistingTerminalTabs, -PreCapturedTerminalTabs, -DesktopOffset, -Alongside, -AdoptUnclaimed, -Append, -PreserveEntry, -ProtectedWindowHandles, -Entry, -StatePath
- **Usage:** `Save-WorkspaceState -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore`, `Save-WorkspaceState -Entry $survivingEntries`

Deriving ownership from the delta rather than from `WorkspaceActions` is the whole point: a single-instance application is only ever recorded against the open that actually launched it, whereas a config-derived record would list it under every workspace that names it.

A plain open **replaces** the file - it reset the virtual desktops, so no earlier open survives it. Every `-Alongside` open **appends**, including for a name that is already tracked, because that is a genuinely separate instance with its own windows. `-Append` covers the remaining case: the second and later workspaces of a single plain `Open-Workspace a, b` run, which must add to the session the first one defined instead of replacing its entry and leaving it untracked. A plain open that is **preserving** live alongside workspaces (see [Get-WorkspaceOpenProtection](#get-workspaceopenprotection)) seeds the replaced file with their entries via `-PreserveEntry` - the plain non-`-Append` path only, because an appending save reads the file back and it already holds them - and forwards `-ProtectedWindowHandles` to the delta so adoption can never claim a preserved workspace's windows or terminal tabs.

Writing is **best-effort**. Any failure is logged as a warning and swallowed, because a snapshot write must never fail an otherwise successful workspace open; the cost is that `Close-Workspace` reports that workspace as untracked. The state directory is created on demand.

Two parameter sets: `Record` builds an entry from a pre-open capture, `Entries` writes an explicit set - used by `Close-Workspace` to persist what remains open after a teardown, and by `Kill-All` to clear the tracker (`-Entry @()`).

| Parameter                | Type      | Description                                                                                                       |
| ------------------------ | --------- | ----------------------------------------------------------------------------------------------------------------- |
| `-Workspace`             | string    | Name of the workspace this entry belongs to. Mandatory in the `Record` set.                                         |
| `-ExistingWindowHandles` | object    | Handles that existed before the open (`HashSet[IntPtr]`, raw values, or objects exposing `.Handle`).                 |
| `-ExistingTerminalTabs`  | hashtable | The pre-open `Get-TerminalTabSnapshot` (window handle -> tab titles).                                               |
| `-PreCapturedTerminalTabs` | hashtable | The matching after snapshot, taken while the terminal was still on the visible desktop. Forwarded to `Get-WorkspaceOpenDelta`, which otherwise reads it itself and pays a desktop round trip. |
| `-DesktopOffset`         | int       | Desktop offset the open used (`0` normally, `+N` for `-Alongside`). Recorded for context.                            |
| `-Alongside`             | switch    | The open was alongside existing desktops; also switches the write from replace to append.                            |
| `-AdoptUnclaimed`        | switch    | Forwarded to `Get-WorkspaceOpenDelta`. First workspace of a plain run only.                                          |
| `-Append`                | switch    | Add to the tracker instead of replacing it, without implying `-Alongside`.                                           |
| `-PreserveEntry`         | object[]  | Preserved alongside entries to carry forward through a plain (replacing) save. Seeded ahead of the new record on the plain non-`-Append` path only. |
| `-ProtectedWindowHandles` | object   | Handles of preserved alongside workspaces, forwarded to `Get-WorkspaceOpenDelta` so adoption never claims them.       |
| `-Entry`                 | object[]  | Write exactly these entries, replacing the file. Mandatory in the `Entries` set; pass `@()` to clear the tracker.     |
| `-StatePath`             | string    | Full path to the state file. Defaults to [Get-WorkspaceStatePath](#get-workspacestatepath).                          |

```powershell
# Record what an open produced (what Open-Workspace does internally)
Save-WorkspaceState -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore -AdoptUnclaimed

# Keep only the workspaces that are still open (what a teardown does)
Save-WorkspaceState -Entry $survivingEntries

# Clear the tracker outright (what Kill-All does)
Save-WorkspaceState -Entry @()
```

**See also:** [Get-WorkspaceOpenDelta](#get-workspaceopendelta), [Get-WorkspaceState](#get-workspacestate), [Format-WorkspaceStateContent](#format-workspacestatecontent), [Close-Workspace](#close-workspace), [Kill-All](system.md#kill-all)

## [Start-Containers](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Start-Containers.ps1)

- **Description:** Starts (or stops) the Docker Compose stacks registered in `Configuration.DockerComposeFiles`, without running any project - so tools like DBeaver can connect while the project APIs/UIs stay closed. The stacks are shared by design (every PostgreSQL project talks to the same centralized containers), so the unit of control is the compose file itself, not a project: with a single configured stack the command is a pure on/off switch and asks nothing; with several, a multi-select menu is shown. After a successful start the compose file's published host ports are printed, so the connection target is obvious.
- **Parameters:** -Name, -Stop, -Down
- **Usage:** `Start-Containers`, `Start-Containers PostgreSQL`, `Start-Containers -Stop`, `Start-Containers -Stop -Down`

Stack values resolve relative to `MachineSpecificPaths.DockerDirectory`; absolute paths are used as-is, so any compose file on disk can be registered (`Redis = "docker-compose.redis.yml"`, `MyStack = "D:\Stacks\compose.yml"`) - the mechanism is not database-specific. `-Stop` runs `docker compose stop` (containers kept, fast to resume); adding `-Down` runs `docker compose down` instead (containers and network removed, volumes kept). Docker Desktop itself stays running either way - that is [DockerWizard](#dockerwizard) `-Stop`'s job.

It also works as a workspace/project action, e.g. `@{ Action = "Start-Containers" }`, for workspaces that want the database up without the servers.

| Parameter | Description                                                                                              |
| --------- | ---------------------------------------------------------------------------------------------------------- |
| `-Name`   | Stack name(s) from `DockerComposeFiles`. Omit to start the single configured stack directly, or pick from the menu when several are configured. |
| `-Stop`   | Stops the selected stacks' compose services (`docker compose stop`) instead of starting them.            |
| `-Down`   | With `-Stop`, removes containers and network (`docker compose down`); volumes are kept. Implies `-Stop`. |

```powershell
# One configured stack: just starts it, no menu (menu appears only with several stacks)
Start-Containers

# Or by name
Start-Containers PostgreSQL

# Stop the containers, keep them for a fast resume
Start-Containers -Stop

# Remove the containers and network, keep the volumes (data survives)
Start-Containers -Stop -Down
```

**See also:** [DockerWizard](#dockerwizard), [Docker-Cleanup](#docker-cleanup), [Resolve-ProjectDockerCompose](#resolve-projectdockercompose), [Run-Project](helper.md#run-project)

## [Test-TerminalTabsAlreadyOpen](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Test-TerminalTabsAlreadyOpen.ps1)

- **Description:** Checks which expected terminal tabs are already open by reading every Windows Terminal window's tab titles via UI Automation - no focus changes, no keystrokes. When UI Automation cannot read a window's tabs, the legacy pass takes over and cycles that window with Ctrl+Tab. Returns a PSCustomObject with `AllOpen` (bool) and `FoundTabs` (array) so callers can decide whether to skip entirely or open only the missing tabs. Reports partially open projects with a list of missing tab names.
- **Parameters:** -ExpectedTabNames, -ProjectName
- **Usage:** `$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("MyProject.Root", "MyProject.DOCS") -ProjectName "MyProject"`

A helper used by project-launching workflows to make terminal setup idempotent. It finds all `WindowsTerminal` windows via `Get-WindowHandle` and reads each window's tab titles through UI Automation (`Get-WindowsTerminalTabTitles`) in one pass per window - no focus stealing, no Ctrl+Tab cycling - matching each title against the expected names. When UI Automation cannot read a window's tabs, the legacy fallback activates that window with `SetForegroundWindow` and walks its tabs with `Ctrl+Tab`, checking up to 20 tabs per window and stopping once it loops back to an already-seen title. It exits early once every expected tab has been found. If all tabs are present it prints a yellow "already open" notice; if only some are present it warns and lists the missing tabs. When Windows Terminal is not running (or no windows are found), it safely returns `AllOpen = $false` with an empty `FoundTabs`.

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

## [Write-WorkspaceBenchmark](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Workflow/Functions/Write-WorkspaceBenchmark.ps1)

- **Description:** Records how long one workspace open took and where the time went: appends a row to the workspace benchmark file ([Get-WorkspaceBenchmarkPath](#get-workspacebenchmarkpath)) and prints a one-line `Timing [Workspace] =>` summary. [Open-Workspace](#open-workspace) calls it once per workspace, when `Configuration.WorkspaceBenchmark.Enabled` is set, with the seconds each configured action took and the phase record `Set-WorkspaceWindowLayout` published ([Get-WorkspaceLayoutTimings](window.md#get-workspacelayouttimings)). The row carries the timestamp, workspace, mode (`Plain` or `Alongside`), the layout outcome and attempt count, the total, the seconds spent in the launch actions (`ActionsSeconds`), in the layout action as a whole (`LayoutSeconds`), in each layout phase (`Preamble`, `Desktops`, `FancyZones`, `Wait`, `Normalize`, `Position`, `Snap`, `Verify`, `Retry`, `Save`), the remainder (`OtherSeconds`, the open's own bookkeeping) and the per-action breakdown as `Name=seconds` pairs. Numbers are written culture-invariant, so the file reads the same on a comma-decimal machine. The summary line lists the phases above 0.05 s, plus `retries N` when the layout needed more than one attempt and the outcome when it is not `Applied`. Writing is best-effort: a failure warns and never fails the open. `-Quiet` suppresses the console line, `-PassThru` emits the row.
- **Parameters:** -Workspace, -TotalSeconds, -ActionTimings, -LayoutTimings, -Alongside, -BenchmarkPath, -Quiet, -PassThru
- **Usage:** `Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 27.5 -ActionTimings @(@{ Action = 'Open-Browser'; Seconds = 0.8 }) -LayoutTimings (Get-WorkspaceLayoutTimings)`, `Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 5.3 -Quiet -PassThru`

| Parameter        | Description                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `-Workspace`     | Workspace the row describes. Mandatory.                                                                   |
| `-TotalSeconds`  | Wall-clock seconds of the whole open, as measured by the caller.                                          |
| `-ActionTimings` | Objects with `Action` and `Seconds`, one per executed action, in order. `Set-WorkspaceWindowLayout` is reported as `LayoutSeconds`, every other action adds to `ActionsSeconds`. |
| `-LayoutTimings` | The record returned by `Get-WorkspaceLayoutTimings`. Omit when no layout ran; the row then reads `NoLayout` with every phase at 0. |
| `-Alongside`     | Marks the row as an alongside open.                                                                       |
| `-BenchmarkPath` | Write to a different file. Defaults to `Get-WorkspaceBenchmarkPath`.                                     |
| `-Quiet`         | Do not print the `Timing =>` summary line.                                                                |
| `-PassThru`      | Also return the row that was written.                                                                     |

```powershell
# What Open-Workspace does at the end of every workspace
Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 27.5 `
    -ActionTimings @(@{ Action = 'Open-Project'; Seconds = 0.4 }, @{ Action = 'Set-WorkspaceWindowLayout'; Seconds = 25.9 }) `
    -LayoutTimings (Get-WorkspaceLayoutTimings)
```

**See also:** [Get-WorkspaceBenchmark](#get-workspacebenchmark), [Get-WorkspaceBenchmarkPath](#get-workspacebenchmarkpath), [Get-WorkspaceLayoutTimings](window.md#get-workspacelayouttimings), [Open-Workspace](#open-workspace)

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
| `Open-ProjectSwagger`                 | Opens the active project's Swagger tab (opt-in; see the note below)   |
| `Open-VSCode`                         | Opens VS Code                                                         |
| `Open-VisualStudio`                   | Opens Visual Studio                                                   |
| `Open-DBeaver`                        | Opens DBeaver                                                         |
| `Open-WhatsApp`                       | Opens WhatsApp                                                        |
| `Open-Outlook`                        | Opens Outlook                                                         |
| `Open-Discord`                        | Opens Discord                                                         |
| `Open-ProjectTerminals-Or-RunProject` | Opens terminals or runs servers                                       |
| `Start-Containers`                    | Brings up the configured Docker Compose stack(s) (no API/UI)         |
| `Set-WorkspaceWindowLayout`           | Applies window layout                                                 |
| `Terminate-WindowsTerminalTabs`       | Closes terminal tabs (e.g., `-OnlyCurrent` to close calling tab)      |
| `Return`                              | Stops action processing                                               |

> Swagger is opt-in and entirely declarative: nothing happens unless a workspace declares the [Open-ProjectSwagger](#open-projectswagger) action (place it after `Open-Project` and `Open-Browser`, with `Parameters = @{ Project = "{SelectedProjects}" }`). It used to be wired into `Open-Workspace`, which auto-added the group to every `Open-Browser` action whether or not the setup used Swagger at all.

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

In `WorkspaceActions`, use `{SelectedProjects}` to hand an action the workspace's project context - the explicit `-Project` argument, else whatever the workspace's `Open-Project` action selected. The token must be the parameter's FULL value, and the parameter is dropped when no project resolves, so the consuming action simply no-ops:

```powershell
WorkspaceActions = @{
    MyWorkspace = @(
        @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
        @{ Action = "Open-ProjectSwagger"; Parameters = @{ Project = "{SelectedProjects}" } }
    )
}
# {SelectedProjects} replaced with the project(s) Open-Project returned
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
# Closes all MyProject-related windows and tabs, keeping the workspace itself open

Close-Workspace
# Or one level up: pick from the workspaces currently open and close everything
# that open produced - windows, terminal tabs, and the emptied virtual desktops
```

The two are not alternatives. `Close-Project` is how you swap projects **inside** a workspace that stays open; `Close-Workspace` ends the workspace. Use `Close-Workspace -WhatIf` first if you want to see the plan.

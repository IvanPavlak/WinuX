# Configuration Overview

The `Configuration.psd1` file is the **central hub** for the entire WinuX system. This single file controls all aspects of bootstrap, system configuration, application management, and workflow automation.

## File Location

```
WinuX/
└── Windows/
    └── PowerShell/
        └── Configuration.psd1    ← Central configuration file
```

## Architecture

The configuration uses a hierarchical structure designed to eliminate duplication while supporting multiple machines from a single file:

```
┌───────────────────────────────────────────────────────────────────────┐
│                    Configuration.psd1                                 │
├───────────────────────────────────────────────────────────────────────┤
│  Universal Constants     │  Machine-independent values                │
│  (paths, URLs, exe)      │  Same across all machines                  │
├──────────────────────────┼────────────────────────────────────────────┤
│  BasePaths               │  Root directories per machine type         │
│  (Dev, User)             │  {Dev} → "C:\Users\You\Development\GitHub" │
├──────────────────────────┼────────────────────────────────────────────┤
│  PathTemplates           │  Common paths using placeholders           │
│  (Projects, SymLinks)    │  "{Dev}\Project" → expanded                │
├──────────────────────────┼────────────────────────────────────────────┤
│  MachineOverrides        │  Machine-specific differences              │
│  (rarely needed)         │  Only store what can't be templated        │
└──────────────────────────┴────────────────────────────────────────────┘
```

## Complete Section Reference

### System Configuration

| Section                    | Purpose                          | Consumer Function               |
| -------------------------- | -------------------------------- | ------------------------------- |
| `GitConfig`                | Git username, email, package ID  | `Install-Git`                   |
| `Locales`                  | Regional settings (hr-HR, en-US) | `Set-Locale`                    |
| `DisplayLanguages`         | UI language settings             | `Set-DisplayLanguage`           |
| `KeyboardLayouts`          | Keyboard layout codes            | `Set-KeyboardLayouts`           |
| `NerdFonts`                | Font configurations              | `Configure-NerdFont`            |
| `ExplorerOptions`          | Windows Explorer settings        | `Set-ExplorerOptions`           |
| `VisualEffects`            | Visual effects (Performance tab) | `Set-VisualEffects`             |
| `AutoEnvironmentVariables` | Environment variables            | `Set-EnvironmentVariables`      |
| `PostgreSqlPasswords`      | Database credentials             | `Configure-PostgreSqlPasswords` |
| `NuGetConfig`              | NuGet source/destination         | `Configure-NuGetConfig`         |
| `Themes`                   | Dark/Light per machine           | `Set-SystemTheme`               |
| `PowerButtonActions`       | Button & lid actions per machine | `Set-PowerButtonActions`        |
| `WallpaperStyles`          | Fill, Fit, Stretch, etc.         | `Set-Wallpaper`                 |
| `WallpaperDarkSettings`    | Dark wallpaper per machine       | `Set-Wallpaper`                 |
| `WallpaperLightSettings`   | Light wallpaper per machine      | `Set-Wallpaper`                 |
| `TaskbarConfiguration*`    | Pinned apps configuration        | `Configure-Taskbar`             |
| `PowerPlans`               | Power plan per machine           | `Set-PowerPlan`                 |
| `SpecialFolders`           | Special folder redirections      | `Set-SpecialFolders`            |
| `DefaultWSLDistribution`   | Default WSL distribution         | `Configure-WSL`                 |

### Path & Repository Management

| Section               | Purpose                    | Consumer Function                              |
| --------------------- | -------------------------- | ---------------------------------------------- |
| `BasePaths`           | Dev/User paths per machine | `Expand-ConfigPaths`                           |
| `PathTemplates`       | All templated paths        | All path-dependent functions                   |
| `SymbolicLinks`       | Source → Target mappings   | `SymbolicLinkMaker`                            |
| `RepositoryGroups`    | Git repos grouped by type  | `Update-Repositories`, `Initialize-Repository` |
| `MachinePathMappings` | Machine-to-path resolution | Path expansion functions                       |

### Project & Workflow Management

| Section                    | Purpose                         | Consumer Function       |
| -------------------------- | ------------------------------- | ----------------------- |
| `Projects`                 | Project names list              | `Open-Project`          |
| `ProjectActions`           | What happens when project opens | `Open-Project`          |
| `ProjectTerminals`         | Terminal tabs per project       | `Open-ProjectTerminals` |
| `RunnableProjects`         | Projects that can be run        | `Run-Project`           |
| `RunnableProjectMappings`  | Run commands per project        | `Run-Project`           |
| `VisualStudioSolutions`    | VS solutions (name + path)      | `Open-VisualStudio`     |
| `VSCodeProjects`           | VS Code projects (name + path)  | `Open-VSCode`           |
| `DotnetProjectsSearchPath` | .NET project search paths       | `Run-Project`           |
| `DotnetEFVersion`          | EF Core tools version           | `EfCoreMigrationWizard` |

### Workspace Management

| Section            | Purpose               | Consumer Function |
| ------------------ | --------------------- | ----------------- |
| `Workspaces`       | Workspace names list  | `Open-Workspace`  |
| `WorkspaceActions` | Actions per workspace | `Open-Workspace`  |

### Application Configuration

| Section            | Purpose                 | Consumer Function |
| ------------------ | ----------------------- | ----------------- |
| `BrowserGroups`    | Hierarchical URL groups | `Open-Browser`    |
| `AcrobatGroups`    | PDF file groups         | `Open-Acrobat`    |
| `AcrobatPdfGroups` | PDF group definitions   | `Open-Acrobat`    |
| `Campaigns`        | D&D campaign list       | `Open-DnD`        |

### Bootstrap Process

| Section           | Purpose                     | Consumer Function                |
| ----------------- | --------------------------- | -------------------------------- |
| `PackageManagers` | WinGet, Scoop, Chocolatey   | `Bootstrap`                      |
| `BootstrapConfig` | Log files, external scripts | `Bootstrap`, `Install-Bootstrap` |

### Machine Type Detection

| Section                 | Purpose                  | Consumer Function      |
| ----------------------- | ------------------------ | ---------------------- |
| `ValidMachineTypes`     | PC, Laptop, Work, Test   | `DetermineMachineType` |
| `HostnameToMachineType` | Hostname → type mapping  | `DetermineMachineType` |
| `DefaultMachineType`    | Fallback machine type    | `DetermineMachineType` |
| `LaptopChassisTypes`    | Chassis types for laptop | `DetermineMachineType` |

### UI & Visual Configuration

| Section                         | Purpose                        | Consumer Function      |
| ------------------------------- | ------------------------------ | ---------------------- |
| `ListFunctionsColors`           | Function list colors           | `List-Functions`       |
| `ShowFunctionDetailsColors`     | Function detail colors         | `Show-FunctionDetails` |
| `LoadingSpinners`               | Spinner animations             | `Loading-Spinner`      |
| `DefaultSpinner`                | Default spinner style          | `Loading-Spinner`      |
| `FunctionDiscrepancyExclusions` | Functions excluded from checks | `List-Functions`       |

### Window Management & FancyZones

| Section                  | Purpose                    | Consumer Function           |
| ------------------------ | -------------------------- | --------------------------- |
| `SimpleLayoutWorkspaces` | Fullscreen-only workspaces | `Set-WorkspaceWindowLayout` |
| `LayoutNumbers`          | Layout to hotkey mapping   | `Apply-FancyZones`          |
| `ZoneNameMappings`       | Zone names to indices      | `Get-FancyZone`             |

### Network & Wake-on-LAN

| Section                   | Purpose                               | Consumer Function                      |
| ------------------------- | ------------------------------------- | -------------------------------------- |
| `WakeOnLanMachines`       | WOL target machines                   | `Send-WakeOnLan`                       |
| `WakeOnLanConfig`         | WOL network settings + ping `Address` | `Send-WakeOnLan`, `Test-MachineOnline` |
| `DefaultWakeOnLanMachine` | Default WOL target                    | `Send-WakeOnLan`                       |
| `KeyboardLayoutSets`      | Named keyboard layout sets            | `Set-KeyboardLayouts`                  |

## Configuration Loading

When PowerShell profile loads or Bootstrap runs:

```powershell
Load-PathConfiguration -RepoRoot "C:\Users\You\Development\GitHub\WinuX"
```

This triggers the following process:

```
┌────────────────────────────────────────────────────────────────┐
│  1. Read Configuration.psd1                                    │
├────────────────────────────────────────────────────────────────┤
│  2. Resolve machine type                                       │
│     └─→ Hostname looked up in HostnameToMachineType            │
│     └─→ Unmapped hostname → DefaultMachineType fallback        │
├────────────────────────────────────────────────────────────────┤
│  3. Expand-ConfigPaths()                                       │
│     └─→ Replace {Dev} with BasePaths.PC.Dev                    │
│     └─→ Replace {User} with BasePaths.PC.User                  │
│     └─→ Replace {MachineType} with "PC"                        │
│     └─→ Replace {RepoRoot} with WinuX path                     │
│     └─→ Replace {AppData} with %APPDATA%                       │
├────────────────────────────────────────────────────────────────┤
│  4. Set Global Variables                                       │
│     └─→ $global:Configuration = Raw config                     │
│     └─→ $global:MachineSpecificPaths = Expanded paths          │
│     └─→ $global:MachineType = "PC"                             │
└────────────────────────────────────────────────────────────────┘
```

## Quick Reference: Common Customizations

### Add a New Machine

1. Add hostname mapping in `HostnameToMachineType`
2. Add base paths in `BasePaths`
3. Add theme in `Themes`
4. Add wallpaper settings in `WallpaperDarkSettings`/`WallpaperLightSettings`
5. Create layout files in `Layouts/{MachineType}/`

→ See [Add New Machine Guide](guides/add-new-machine.md)

### Add a New Project

1. Add paths in `PathTemplates.Projects`
2. Add to `Projects` list
3. Add `ProjectActions` entry
4. Optionally add to `VSCodeProjects`, `VisualStudioSolutions`, `RunnableProjects`

→ See [Add New Project Guide](guides/add-new-project.md)

### Add a New Repository

1. Add URL in `Universal.GitHub.Private` or `Universal.GitHub.YourGroup`
2. Add a repository entry in `RepositoryGroups`

→ See [Add New Repository Guide](guides/add-new-repository.md)

### Add a Symbolic Link

1. Add entry in `PathTemplates.SymbolicLinks`
2. Run `SymbolicLinkMaker` or `Bootstrap`

→ See [Add Symbolic Link Guide](guides/add-symbolic-link.md)

### Add a Workspace

1. Add to `Workspaces` list
2. Add `WorkspaceActions` entry
3. Create layout file in `Layouts/{MachineType}/`

→ See [Add New Workspace Guide](guides/add-new-workspace.md)

## Example: Full Project Configuration

```powershell
# ═══════════════════════════════════════════════════════════════
# Adding "MyProject" - Complete Example
# ═══════════════════════════════════════════════════════════════

# 1. Add GitHub URL (if new repo)
Universal = @{
    GitHub = @{
        Private = @{
            MyProject = "/YourUsername/MyProject.git"
        }
    }
}

# 2. Add project paths in PathTemplates.Projects
PathTemplates = @{
    Projects = @{
        MyProject = @{
            Root     = "{Dev}\MyProject"
            Solution = "{Dev}\MyProject\MyProject.sln"
            Api      = "{Dev}\MyProject\src\Api"
            Ui       = "{Dev}\MyProject\ui"
        }
    }
}

# 3. Add repository entry
RepositoryGroups = @(
    @{ Private = @(
            @{ Name = "MyProject"; UrlPath = "Universal.GitHub.Private.MyProject"; LocalPath = "Projects.MyProject.Root" }
        )
    }
)

# 4. Add to Projects list
Projects = @("WinuX", "MyProject", ...)

# 5. Define project actions
ProjectActions = @{
    MyProject = @(
        @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "MyProject" } }
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } }
        @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "MyProject" } }
    )
}

# 6. Add to VS Code projects (optional)
VSCodeProjects = @(
    @{ Name = "WinuX"; Path = "Projects.Self.Root" }
    @{ Name = "MyProject"; Path = "Projects.MyProject.Root" }
)

# 7. Add to Visual Studio solutions (optional)
VisualStudioSolutions = @(
    @{ Name = "MyProject"; Solution = "Projects.MyProject.Solution" }
)

# 8. Add terminal configuration (optional)
ProjectTerminals = @(
    @{ Name = "WinuX"; BasePath = "Projects.Self"; Paths = @("ROOT", "DOCS") }
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }  # Opens 2 terminal tabs
)

# 9. Add runnable project (optional)
RunnableProjects = @("MyProject", ...)
RunnableProjectMappings = @(
    @{ Name = "MyProject"; Commands = @("dnr", "nir") }  # API=dotnet run, UI=npm install+run
)
```

## Configuration Sections Detail

### Universal Constants

```powershell
Universal = @{
    # Executable paths
    FirefoxExe      = "C:\Program Files\Mozilla Firefox\firefox.exe"
    DbeaverExe      = "{User}\AppData\Local\DBeaver\dbeaver.exe"

    # Browser configurations
    Browsers = @{
        Firefox = @{
            Exe          = "C:\Program Files\Mozilla Firefox\firefox.exe"
            PrivateArg   = "-private-window"
            NewWindowArg = "-new-window"
        }
    }

    # GitHub repository URLs
    GitHub = @{
        Base    = "https://YourUsername@github.com"
        Private = @{
            WinuX = "/YourUsername/WinuX.git"
            Obsidian = "/YourUsername/Obsidian.git"
        }
    }
}
```

### Machine-Specific Settings

```powershell
# Theme per machine
Themes = @{
    "PC"     = "Dark"
    "Laptop" = "Dark"
    "Work"   = "Dark"
}

# Wallpaper per machine (supports multi-monitor)
WallpaperDarkSettings = @{
    "PC" = @{
        Monitors = @(
            @{ File = "Space1.jpg"; Style = "Stretch" }
            @{ File = "Space2.jpg"; Style = "Stretch" }
        )
    }
    "Laptop" = @{ File = "BlackHole.png"; Style = "Fill" }
}
```

## Next Steps

- Learn about the [Placeholder System](placeholder-system.md)
- Understand [Machine Types](machine-types.md)
- Follow the [How-To Guides](guides/add-new-project.md) for step-by-step tutorials

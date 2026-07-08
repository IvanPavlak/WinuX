# Add New Project

This guide shows how to add a new development project to WinuX for use with `Open-Project` and workspace automation.

## Steps Overview

1. Add GitHub URL in `Universal.GitHub`
2. Add project paths in `PathTemplates.Projects`
3. Add to `VisualStudioSolutions` (if using Visual Studio)
4. Add to `VSCodeProjects` (if using VS Code)
5. Add to `ProjectTerminals` (for terminal tabs)
6. Add a repository entry in `RepositoryGroups` (if Git repo)
7. Add to `Projects` list
8. Add Swagger URL to `BrowserGroups` (if using Swagger)
9. Define project actions in `ProjectActions`
10. Add to `RunnableProjects` + `RunnableProjectMappings` (if runnable)

## Step 1: Add GitHub URL

In `Universal.GitHub`, add the repository URL under the appropriate group:

```powershell
Universal = @{
    GitHub = @{
        # For private/personal repos:
        Private = @{
            MyNewProject = "/YourUsername/MyNewProject.git"
        }
        # For work repos:
        MyOrg = @{
            MyNewProject = "/my-org/my-new-project"
        }
    }
}
```

## Step 2: Add Project Paths

In `Configuration.psd1` under `PathTemplates.Projects`, add the physical directory mappings:

```powershell
Projects = @{
    # Under appropriate group...
    MyNewProject = @{
        Root     = "{Dev}\MyNewProject"
        Solution = "{Dev}\MyNewProject\MyNewProject.sln"
        Api      = "{Dev}\MyNewProject\src\Api"
        Ui       = "{Dev}\MyNewProject\ui"
    }
}
```

**Common path keys:**

| Key        | Purpose                       | Notes                                                                                                       |
| ---------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Root`     | Main project directory        | Used by VS Code, repository cloning                                                                         |
| `Solution` | `.sln` file path              | Used by Visual Studio                                                                                       |
| `Api`      | Backend API project directory | **Must point to the folder where `dotnet run` works** (i.e., where the `.csproj` is), not the solution root |
| `Ui`       | Frontend UI directory         | Used by VS Code and terminal tabs                                                                           |
| `Backend`  | Alternative to Api            | Used when the API folder has a different name                                                               |

> [!WARNING]
> The `Api` path must point to the actual project folder (e.g., `src\Api`), not the solution root. The `dnr` (DotnetRun) command executes `dotnet run` in this directory.

## Step 3: Add Visual Studio Mapping (if applicable)

```powershell
VisualStudioSolutions = @(
    @{ Name = "ExistingProject"; Solution = "Projects.ExistingProject.Solution" }
    @{ Name = "MyNewProject"; Solution = "Projects.MyNewProject.Solution" }    # ← Add here
)
```

## Step 4: Add VS Code Mapping (if applicable)

```powershell
VSCodeProjects = @(
    @{ Name = "ExistingProject"; Path = "Projects.ExistingProject.Root" }
    @{ Name = "MyNewProject"; Path = "Projects.MyNewProject.Root" }    # ← Add here
)
```

> [!NOTE]
> If your project has separate backend and UI repos opened in separate VS Code windows, add each as a separate entry (e.g., `@{ Name = "MyProject"; Path = "..." }` and `@{ Name = "MyProject-UI"; Path = "..." }`).

## Step 5: Add Terminal Configuration

```powershell
ProjectTerminals = @(
    @{ Name = "ExistingProject"; BasePath = "Projects.ExistingProject"; Paths = @("ROOT") }
    @{ Name = "MyNewProject"; BasePath = "Projects.MyNewProject"; Paths = @("API", "UI") }    # ← Add here
)
```

Terminal tabs will be named `MyNewProject.API` and `MyNewProject.UI`.

> [!WARNING]
> `ProjectTerminals` only defines available tab paths. To actually open those tabs from `Open-Project` (and from workspace flows like `w AlgoProject` that call `Open-Project`), the same project **must** include this action in `ProjectActions`:
> `@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }`
> Without that action, only other configured actions (for example `Open-VSCode`) will run, and no terminal tabs will open.

**Special path values:**

| Value       | Behavior                                        |
| ----------- | ----------------------------------------------- |
| `"ROOT"`    | Opens at the project root path                  |
| `"DEFAULT"` | Opens a plain terminal at the default directory |
| `"WSL"`     | Opens a WSL tab using `DefaultWSLDistribution`  |

## Step 6: Add Repository Mapping (if Git repo)

```powershell
RepositoryGroups = @(
    @{ Private = @(
            @{ Name = "MyNewProject"; UrlPath = "Universal.GitHub.Private.MyNewProject"; LocalPath = "Projects.MyNewProject.Root" }
        )
    }
)
```

This enables `Update-Repositories` to clone and update the repository.

## Step 7: Add to Projects List

```powershell
Projects = @(
    "WinuX",
    "MyProject",
    "MyNewProject"    # ← Add here
)
```

This makes it available in the `Open-Project` interactive menu.

## Step 8: Add Swagger URL (if applicable)

Add the Swagger URL to the `Swagger` group in `BrowserGroups`. The `Name` must match the project name (case-insensitive):

```powershell
BrowserGroups = @(
    @{ Swagger = @(
        @{ Name = "MyNewProject"; Url = "http://localhost:5000/swagger/index.html" }
    )}
)
```

No separate mapping is needed - when a workspace runs an `Open-Browser` action, [Resolve-SwaggerBrowserGroup](../../modules/workflow.md#resolve-swaggerbrowsergroup) looks up the `Swagger` group by the active project's name and adds it (unless it is already open).

The matching window-layout entry recognizes the Swagger window across browsers and backend states: the rendered `Swagger UI` page title (any browser, backend up), Firefox's `Problem loading page` title, and the `localhost` host title that Chromium browsers (Chrome/Edge/Brave) show on a failed load (backend down). Because of this, a project with **no real API** can still reserve its window-layout zone by pointing at an unused `localhost` port, which always renders as a "problem page":

```powershell
# Placeholder for a project with no API/Swagger: the unused port renders a
# "problem page" so the project's window-layout zone is still filled.
@{ Name = "MyScriptsProject"; Url = "http://localhost:5999/swagger/index.html" }
```

## Step 9: Define Project Actions

In `ProjectActions`, define what happens when `Open-Project MyNewProject` is executed:

```powershell
ProjectActions = @{
    MyNewProject = @(
        @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
        @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
    )
}
```

**`{ProjectName}`** is automatically replaced with the actual project name at runtime.

**Available actions:**

| Action                                | Parameters               | Description                       |
| ------------------------------------- | ------------------------ | --------------------------------- |
| `Open-VisualStudio`                   | `@{ Solution = "..." }`  | Opens Visual Studio with solution |
| `Open-VSCode`                         | `@{ Folder = "..." }`    | Opens VS Code with folder         |
| `Open-ProjectTerminals-Or-RunProject` | `@{ Project = "..." }`   | Opens terminals or runs project   |
| `Open-Browser`                        | `@{ Groups = @("...") }` | Opens browser with URL groups     |
| `Open-Obsidian`                       | -                        | Opens Obsidian vault              |
| `Open-DBeaver`                        | -                        | Opens DBeaver                     |

## Step 10: Add to Runnable Projects (if applicable)

```powershell
RunnableProjects = @(
    "MyProject",
    "MyNewProject"    # ← Add here
)

RunnableProjectMappings = @(
    @{
        Name              = "MyNewProject"
        Commands          = @("dnr", "nir")
        DatabaseProviders = @("PostgreSQL")
    }
)
```

**Commands must match the `Paths` order in `ProjectTerminals`:**

| Paths entry | Command     | What it runs                                 |
| ----------- | ----------- | -------------------------------------------- |
| `API` (1st) | `dnr` (1st) | `dotnet run` in the Api directory            |
| `UI` (2nd)  | `nir` (2nd) | `npm install; npm start` in the Ui directory |

**Available run commands:**

| Command                    | Alias for                                           | Use when                                       |
| -------------------------- | --------------------------------------------------- | ---------------------------------------------- |
| `"dnr"`                    | `DotnetRun` (`dotnet run`)                          | .NET API projects                              |
| `"dnbr"`                   | `DotnetBuildAndRun` (`dotnet build` + `dotnet run`) | .NET projects needing explicit build           |
| `"nir"`                    | `NpmInstallAndStart` (`npm install; npm start`)     | npm-based UI projects                          |
| `"npm run dev"`            | Direct command                                      | UI projects with `dev` script                  |
| `"pnpm install; pnpm dev"` | Direct command                                      | pnpm-based UI projects (e.g., monorepos)       |
| `""`                       | No command                                          | Path that only needs a terminal tab, no server |

**`DatabaseProviders`** - if the project uses a database, specify the provider(s). When multiple providers are listed, `Run-Project` will prompt for selection. Docker Compose is automatically started via `DockerWizard` when configured.

## Real-World Example: Adding the MonorepoProject Project

MonorepoProject is a monorepo under `MyOrg` with the structure `apps/api/` (.NET) and `apps/ui/` (pnpm/Vite). Here is every section that was added:

```powershell
# 1. GitHub URL
MyOrg = @{
    MonorepoProject = "/my-org/monorepo-project"
}

# 2. Project Paths - Note: Api points to src/Api (where .csproj lives), not apps/api
MyOrg = @{
    MonorepoProject = @{
        Root     = "{Dev}\MyOrg\monorepo-project"
        Solution = "{Dev}\MyOrg\monorepo-project\apps\api\MonorepoProject.sln"
        Api      = "{Dev}\MyOrg\monorepo-project\apps\api\src\Api"
        Ui       = "{Dev}\MyOrg\monorepo-project\apps\ui"
    }
}

# 3. Visual Studio
VisualStudioSolutions = @(
    @{ Name = "OtherProject"; Solution = "Projects.MyOrg.OtherProject.Solution" }
    @{ Name = "MyProject"; Solution = "Projects.MyOrg.MyProject.Solution" }
    @{ Name = "FourthProject"; Solution = "Projects.MyOrg.FourthProject.Solution" }
    @{ Name = "ThirdProject"; Solution = "Projects.MyOrg.ThirdProject.Solution" }
    @{ Name = "MonorepoProject"; Solution = "Projects.MyOrg.MonorepoProject.Solution" }
    @{ Name = "TrainingProject"; Solution = "Projects.TrainingProject.Solution" }
)

# 4. VS Code
VSCodeProjects = @(
    @{ Name = "WinuX"; Path = "Projects.Self.Root" }
    @{ Name = "OtherProject"; Path = "Projects.MyOrg.OtherProject.Root" }
    @{ Name = "MyProject"; Path = "Projects.MyOrg.MyProject.Backend" }
    @{ Name = "ThirdProject"; Path = "Projects.MyOrg.ThirdProject.Root" }
    @{ Name = "MonorepoProject"; Path = "Projects.MyOrg.MonorepoProject.Root" }
    @{ Name = "TrainingProject"; Path = "Projects.TrainingProject.Root" }
)

# 5. Terminal Tabs
ProjectTerminals = @(
    @{ Name = "WinuX"; BasePath = "Projects.Self"; Paths = @("ROOT", "DOCS") }
    @{ Name = "OtherProject"; BasePath = "Projects.MyOrg.OtherProject"; Paths = @("API", "UI") }
    @{ Name = "MyProject"; BasePath = "Projects.MyOrg.MyProject"; Paths = @("API", "UI") }
    @{ Name = "ThirdProject"; BasePath = "Projects.MyOrg.ThirdProject"; Paths = @("API", "UI") }
    @{ Name = "MonorepoProject"; BasePath = "Projects.MyOrg.MonorepoProject"; Paths = @("API", "UI") }
    @{ Name = "TrainingProject"; BasePath = "Projects.TrainingProject"; Paths = @("API", "UI") }
)

# 6. Repository
RepositoryGroups = @(
    @{ Work = @(
            @{ Name = "MonorepoProject"; UrlPath = "Universal.GitHub.MyOrg.MonorepoProject"; LocalPath = "Projects.MyOrg.MonorepoProject.Root" }
        )
    }
)

# 7. Projects List
Projects = @("WinuX", "MyProject", "ThirdProject", "MonorepoProject", "OtherProject", "TrainingProject")

# 8. Swagger - Name must match project name (case-insensitive)
BrowserGroups = @(
    @{ Swagger = @(
        @{ Name = "MonorepoProject"; Url = "http://localhost:3000/swagger/index.html" }
    )}
)

# 9. Project Actions
MonorepoProject = @(
    @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
    @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
    @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
)

# 10. Runnable - uses pnpm, not npm, so direct command instead of "nir"
RunnableProjects = @("MyProject", "ThirdProject", "MonorepoProject")
RunnableProjectMappings = @(
    @{
        Name              = "MonorepoProject"
        Commands          = @("dnr", "pnpm install; pnpm dev")
        DatabaseProviders = @("PostgreSQL")
    }
)
```

> [!TIP]
> When adding a project that uses a non-standard package manager (e.g., pnpm instead of npm), use a direct command string instead of a predefined alias like `"nir"`. The command is executed as-is in the terminal.

## Usage

After configuration:

```powershell
# Open project (interactive menu)
Open-Project

# Open specific project
Open-Project MyNewProject

# Open and run servers
Open-Project MyNewProject -RunApp

# Or via workspace
w MyOrg MyNewProject -RunApp
```

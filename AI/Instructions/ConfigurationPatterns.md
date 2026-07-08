# Configuration Patterns

> **Purpose**: Guide for modifying `Configuration.psd1` - the central configuration hub.
> **File**: `Windows/PowerShell/Configuration.psd1`

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## Placeholder System

All paths use placeholders expanded at runtime by `Expand-ConfigPaths`:

| Placeholder     | Example Value                           | Source                             |
| --------------- | --------------------------------------- | ---------------------------------- |
| `{Dev}`         | `C:\Users\You\Development\GitHub`       | `BasePaths.<MachineType>.Dev`      |
| `{User}`        | `C:\Users\You`                          | `BasePaths.<MachineType>.User`     |
| `{MachineType}` | `PC`                                    | `DetermineMachineType` result      |
| `{RepoRoot}`    | `C:\Users\You\Development\GitHub\WinuX` | Resolved at Load-PathConfiguration |
| `{AppData}`     | `C:\Users\You\AppData\Roaming`          | Derived from `{User}`              |

**Rule**: Always use placeholders for paths. Never hardcode machine-specific paths.

## Adding a Browser Group

Browser groups live in the `BrowserGroups` array. Three patterns:

### Simple URL list

```powershell
@{ GroupName = @("https://url1.com", "https://url2.com") }
```

### Named URLs (recommended)

```powershell
@{ GroupName = @(
    @{ Name = "Label1"; Url = "https://url1.com" }
    @{ Name = "Label2"; Url = "https://url2.com" }
)}
```

### Nested groups

```powershell
@{ ParentGroup = @(
    @{ ChildGroup1 = @(
        @{ Name = "Label"; Url = "https://..." }
    )}
    @{ ChildGroup2 = @(
        @{ Name = "Label"; Url = "https://..." }
    )}
)}
```

**Constraints**:

- Group names and individual `Name` values must be **globally unique** across all groups
- Names are used for direct access via `Open-Browser GroupName` or `Open-Browser Label`
- Nesting depth is unlimited

## Adding a Workspace

### Step 1: Add to workspace list

```powershell
Workspaces = @(
    "Existing1", "Existing2", "NewWorkspace"  # ← Add here
)
```

### Step 2: Define workspace actions

```powershell
WorkspaceActions = @{
    NewWorkspace = @(
        @{ Action = "Open-Project"; Parameters = @{ Project = "ProjectName" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Group1", "Group2") } }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "NewWorkspace" } }
    )
}
```

**Available actions**: Any exported function name. Common ones:

- `Open-Project` - with `@{ Project = "Name" }`
- `Open-Browser` - with `@{ Groups = @("...") }`
- `Set-WorkspaceWindowLayout` - with `@{ WorkspaceName = "..." }`
- `Open-Obsidian`, `Open-DBeaver`, `Open-Outlook`, `Open-Discord`
- `Send-WakeOnLan`, `Training-Backup`, `Test-PrivacyStatus`
- `Return` - **special**: stops processing remaining actions

**Parameter forwarding**: Command-line parameters passed to `Open-Workspace` are automatically forwarded to actions that accept them (via `Get-FilteredParams`).

## Adding a Project

### Step 1: Add to project list

```powershell
Projects = @(
    "Existing1", "Existing2", "NewProject"  # ← Add here
)
```

### Step 2: Define project actions

```powershell
ProjectActions = @{
    NewProject = @(
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
        @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
    )
}
```

`{ProjectName}` is replaced with the actual project name at runtime.

### Step 3: (Optional) Add to VisualStudioSolutions

```powershell
VisualStudioSolutions = @(
    @{ Name = "Existing"; Solution = "Projects.Existing.Solution" }
    @{ Name = "NewProject"; Solution = "Projects.NewProject.Solution" }   # ← Add here
)
```

### Step 4: (Optional) Add to VSCodeProjects

```powershell
VSCodeProjects = @(
    @{ Name = "Existing"; Path = "Projects.Existing.Root" }
    @{ Name = "NewProject"; Path = "Projects.NewProject.Root" }           # ← Add here
)
```

### Step 5: (Optional) Add to ProjectTerminals

```powershell
ProjectTerminals = @(
    @{ Name = "Existing"; BasePath = "Projects.Existing"; Paths = @("ROOT") }
    @{ Name = "NewProject"; BasePath = "Projects.NewProject"; Paths = @("API", "UI") }  # ← Add here
)
```

Path special values in Paths array:

- `"ROOT"` - project root directory
- `"DEFAULT"` - plain terminal at default directory
- `"WSL"` - opens WSL tab using DefaultWSLDistribution
- `@{ Key = "Name"; Path = "C:\path" }` - custom explicit path

### Step 6: (Optional) Add to RunnableProjects

```powershell
RunnableProjects = @(
    "Existing", "NewProject"  # If it can be run via Run-Project
)
```

## Adding a Symbolic Link

```powershell
SymbolicLinks = @{
    NewApp = @{
        Path   = "{User}\path\to\where\link\should\be"
        Target = "{RepoRoot}\path\to\actual\file"
    }
}
```

For apps with multiple config files, nest them:

```powershell
SymbolicLinks = @{
    NewApp = @{
        Settings = @{
            Path   = "{User}\AppData\Local\NewApp\settings.json"
            Target = "{RepoRoot}\NewApp\settings.json"
        }
        Config = @{
            Path   = "{AppData}\NewApp\config.yaml"
            Target = "{RepoRoot}\NewApp\config.yaml"
        }
    }
}
```

**After adding**: Run `SymbolicLinkMaker` to create the links. Requires Developer Mode enabled.

## Adding a Machine Type

1. Add to `ValidMachineTypes`:

```powershell
ValidMachineTypes = @("PC", "Laptop", "Work", "Test", "NewMachine")
```

2. Add hostname mapping:

```powershell
HostnameToMachineType = @{
    "DESKTOP-GAMING"  = "PC"
    "LAPTOP-PERSONAL" = "Laptop"
    "NewHostname"     = "NewMachine"  # ← Add
}
```

3. Add base paths:

```powershell
BasePaths = @{
    NewMachine = @{
        Dev  = "C:\Users\Username\Development\GitHub"
        User = "C:\Users\Username"
    }
}
```

4. Create machine-specific config files:
    - `FastFetch/Windows/config_NewMachine.jsonc`
    - `Windows/Oh-My-Posh/WinuX_NewMachine.omp.json`
    - `Windows/Rainmeter/Rainmeter_NewMachine.ini`
    - Window layout `.psd1` files

## General Rules

1. **Test after changes**: Run `Reload-PowerShellProfile` or restart terminal to verify
2. **Keep alphabetical order**: Within lists and hashtable keys where possible
3. **Comment consumer functions**: Use `# → Consumer: FunctionName` comments
4. **Use existing patterns**: Look at neighboring entries for format reference
5. **Placeholder paths only**: Never hardcode `C:\Users\You\...` - use `{User}\...`

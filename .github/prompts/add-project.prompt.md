---
description: "Add a new project with actions, terminal tabs, and path mappings to Configuration.psd1."
argument-hint: "Project name and setup (e.g., 'NewApp with VS Code, terminals, and API/UI paths')"
agent: "agent"
---

# Add Project

Add a project to Configuration.psd1 using `Add-Project`.

## Steps

1. Ask the user for:
    - **Project name**
    - **IDE**: VS Code (`Open-VSCode`), Visual Studio (`Open-VisualStudio`), or both
    - **Terminal tabs**: titles and paths (DEFAULT for root, WSL for WSL tab, or subdirectory)
    - **Runnable**: can the project be launched via `Run-Project`?
    - **Path mappings**: BasePath (dot-notation like "Projects.MyProject") and path names

2. Call the configuration function:

```powershell
Add-Project -Name "NewApp" -Actions @(
    @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
    @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
) -TerminalTabs @(
    @{ Title = "Root"; Path = "DEFAULT" }
    @{ Title = "API"; Path = "{ProjectName}\api" }
) -BasePath "Projects.NewApp" -Paths @("ROOT", "API") -Runnable
```

3. Remind user to add the project path to `PathTemplates.Projects` in Configuration.psd1 if needed.

## Notes

- `{ProjectName}` is replaced with the actual project name at runtime
- Terminal tab `Path = "DEFAULT"` opens at project root
- Terminal tab `Path = "WSL"` opens a WSL session

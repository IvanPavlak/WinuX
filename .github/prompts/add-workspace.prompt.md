---
description: "Add a new workspace with actions to Configuration.psd1 using the Configuration module."
argument-hint: "Workspace name and what it should open (e.g., 'Trading with browser groups and layout')"
agent: "agent"
---

# Add Workspace

Add a workspace to Configuration.psd1 using `Add-Workspace`.

## Steps

1. Ask the user for:
    - **Workspace name**
    - **Actions** to run when opening (Open-Project, Open-Browser, Set-WorkspaceWindowLayout, etc.)
    - **Browser groups** to open (if any)

2. Call the configuration function:

```powershell
Add-Workspace -Name "WorkspaceName" -Actions @(
    @{ Action = "Open-Project"; Parameters = @{ Project = "ProjectName" } }
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Group1", "Group2") } }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "WorkspaceName" } }
)
```

3. Ask if they also need a window layout file created (`Add-WindowLayout`).

## Available Actions

Common actions: `Open-Project`, `Open-Browser`, `Set-WorkspaceWindowLayout`, `Open-Obsidian`, `Open-DBeaver`, `Open-Outlook`, `Open-Discord`, `Send-WakeOnLan`, `Return` (stops processing).

## Machine-Specific Actions

If an action should only run on some machines, add `Machine = "PC/Work"` (detected machine type) or `LayoutMachine = "Laptop/Work"` (the layout set the window layout is read from) to that entry. If it runs everywhere but a parameter differs per machine, keep one entry and add a `MachineParameters` or `LayoutMachineParameters` table keyed by the same scope strings, e.g. `@{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }` (use `LayoutMachineParameters` for window counts that must match the layout file; a `$null` removes the parameter). `Add-Workspace` writes every one of these keys through unchanged.

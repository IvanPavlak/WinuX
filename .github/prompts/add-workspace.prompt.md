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

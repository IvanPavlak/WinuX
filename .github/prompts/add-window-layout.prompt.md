---
description: "Create a window layout file for a workspace and optionally add to SimpleLayoutWorkspaces."
argument-hint: "Workspace name and machine types (e.g., 'MyWorkspace for PC and Laptop')"
agent: "agent"
---

# Add Window Layout

Create window layout files using `Add-WindowLayout`.

## Steps

1. Ask the user for:
    - **Workspace name** (should match a workspace in Configuration.psd1)
    - **Machine types** to create layouts for (PC, Laptop, Work, Test - or all)
    - **Simple layout?** (layout-only, no window positioning)

2. Call the configuration function:

```powershell
Add-WindowLayout -WorkspaceName "MyWorkspace" -MachineType @("PC", "Laptop")
```

For simple layouts (no window positioning):

```powershell
Add-WindowLayout -WorkspaceName "MyWorkspace" -MachineType @("PC", "Laptop") -Simple
```

3. After creation, remind user to:
    - Edit the generated `.psd1` file to define actual window positions
    - Use `Visualize-Layouts -Layout "MyWorkspace_PC" -Update` to generate ASCII visualization
    - Reference `ZoneNameMappings` in Configuration.psd1 for available zone names

## Layout File Location

`Windows/PowerShell/Modules/Window/Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1`

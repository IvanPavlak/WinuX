# Add New Workspace

This guide shows how to create a new workspace for `Open-Workspace`.

## What is a Workspace?

A workspace is a collection of actions that set up a complete working environment:

- Open applications (browser, Obsidian, etc.)
- Open projects (VS Code, Visual Studio, terminals)
- Apply window layouts (position windows on screen)
- Run development servers

## Steps Overview

1. Define the workspace in `WorkspaceActions`
2. Create window layout file
3. Generate layout visualization

## Step 1: Define the Workspace in WorkspaceActions

`WorkspaceActions` is an ordered list: one single-key hashtable per workspace, in the order the `Open-Workspace` menu offers them. Adding the entry is what puts the workspace in the menu - there is no separate workspace list.

```powershell
WorkspaceActions = @(
    # ... the workspaces already defined ...

    @{ MyNewWorkspace = @(
            @{ Action = "Open-Obsidian" }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "YouTube") } }
            @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
            @{ Action = "Open-DBeaver" }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyNewWorkspace" } }
            @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
        )
    }
)
```

### Available Actions

| Action                          | Description                   | Parameters                                                       |
| ------------------------------- | ----------------------------- | ---------------------------------------------------------------- |
| `Open-Obsidian`                 | Opens Obsidian, into the same-named Obsidian workspace when one exists | None, `Default = $true` to never prompt, or `Workspace = "Name"` to force one |
| `Open-Browser`                  | Opens browser with URL groups | `Groups = @("AI", "Tools")`, `Instances = N`, `Override = $true` |
| `Open-Project`                  | Opens a project               | `Project = "ProjectName"` or empty for prompt                    |
| `Open-VSCode`                   | Opens VS Code                 | `Folder = "FolderName"`                                          |
| `Open-VisualStudio`             | Opens Visual Studio           | `Solution = "SolutionName"`                                      |
| `Open-DBeaver`                  | Opens DBeaver                 | None                                                             |
| `Open-WhatsApp`                 | Opens WhatsApp                | None                                                             |
| `Open-Outlook`                  | Opens Outlook                 | None                                                             |
| `Open-Discord`                  | Opens Discord                 | None                                                             |
| `Open-Acrobat`                  | Opens PDFs                    | `Pdf = "GroupName"`                                              |
| `Open-DnD`                      | Opens D&D resources           | `Campaign = "Name"` (else a menu), `FoundryVTT = $true`          |
| `Open-SecureBrowser`            | Opens Tor + VPN               | None                                                             |
| `Send-WakeOnLan`                | Wakes a machine               | None                                                             |
| `Set-WorkspaceWindowLayout`     | Applies window layout         | `WorkspaceName = "Name"`                                         |
| `Terminate-WindowsTerminalTabs` | Closes terminal tabs          | `OnlyCurrent = $true`                                            |
| `Test-PrivacyStatus`            | Tests VPN/Tor status          | None                                                             |
| `Return`                        | Stops processing              | None                                                             |

### Machine-Specific Actions

An action that should only run on some machines carries a scope, and an action that runs everywhere but differs per machine carries a table; every other action runs everywhere unchanged. `Machine` / `MachineParameters` are matched against the detected machine type, `LayoutMachine` / `LayoutMachineParameters` against the layout set the window layout is read from (`Get-LayoutMachineType` - the detected type unless `LayoutMachineTypeOverrides` or `SmallDisplayMachineType` redirects it). Use the layout axis for anything that produces windows the layout has to place, so the window count follows the layout file:

```powershell
MyNewWorkspace = @(
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
    @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject"; RunApp = $true }; MachineParameters = @{ "Laptop/Work" = @{ RunApp = $null } } }
    @{ Action = "Open-Outlook"; Machine = "Work" }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyNewWorkspace" } }
)
```

The two-window layout in `Layouts/PC/` and the one-window layouts in `Layouts/Laptop/` and `Layouts/Work/` then each get exactly the windows they describe from one browser entry: `Parameters` is the default, the `PC` row adds `Instances = 2` on the PC's own layout set, and a row value of `$null` removes a parameter (`RunApp` away from the desktop). Unknown tokens are reported, not ignored. See [Resolve-WorkspaceActions](Resolve-WorkspaceActions.md).

### Workspaces Built From a Template

When several workspaces share one action list - one per repository, say - write the list once in `WorkspaceTemplates` and stamp it out per workspace. Every templated workspace keeps its own name, so its layout file (`<Name>_<MachineType>.psd1`), tracker entry and Obsidian workspace stay its own. The base ships a generic `Project` template (browser group named like the workspace, VS Code folder, layout, desktop 1, close the launching tab):

```powershell
WorkspaceActions = @(
    @{ MyProject = @{ Template = "Project" } }
    @{ MyRepo = @{
            Template  = "Project"
            Variables = @{ Repository = "MyRepoDocs" }                                                   # browser group name
            Overrides = @{ "Open-Browser" = @{ Parameters = @{ Groups = @("{Repository}", "AI") } } }    # merge over one template action
            Add       = @( @{ Action = "Open-Obsidian"; After = "Open-VSCode" } )                         # one more action
        }
    }
)
```

- `Variables` set the template's `{Name}` placeholders for this workspace; `Open-Workspace MyRepo -Repository OtherGroup` sets one for a single open (it is not forwarded to the actions).
- `Overrides` are keyed by the template action's `Id`, else its action name; `$null` drops a parameter, or the whole action (`"Open-Browser" = $null`).
- `Add` inserts before the template's first `Set-WorkspaceWindowLayout` unless `Before` / `After` names an anchor.
- `{Workspace}` is the workspace's own name, in plain workspaces too.

`Add-Workspace -Name MyProject -Template Project` writes the one-line form. A templated entry that does not expand (unknown template, missing variable, unknown placeholder, ambiguous override, bad anchor) is reported at load and by `Test-ConfigurationSchema`, and opening it opens nothing. See [Workspace Templates](../../configuration-reference.md#workspace-templates) and [Resolve-WorkspaceTemplate](../helper/Resolve-WorkspaceTemplate.md).

### Project-Specific Actions

The project(s) an open is for are known before anything launches - `-Project` on the command line, else the project menu (shown up front when `Open-Project` has no fixed project), else the fixed `Open-Project` project. Actions can depend on them the way they depend on the machine:

```powershell
MyOrg = @(
    @{ Action = "Open-Project" }
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") }; ProjectParameters = @{ MyProject = @{ Groups = @("AI", "MyProjectDocs") } } }
    @{ Action = "Open-DBeaver"; Project = "MyProject/OtherProject" }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
)
```

`Project` runs an action only for those projects (`All` or absent = always); `ProjectParameters` rows merge over `Parameters` after the machine tables, and with several selected projects the later one wins. Tokens must be `ProjectActions` names. The same projects pick the layout file's `ProjectOverrides` (see [Configure Window Layout](../window/configure-window-layout.md#project-variants-of-a-layout)).

### Action Order Matters

Actions execute sequentially. Typically:

1. Open applications first
2. Apply window layout near the end (windows need to exist first)
3. Terminate calling tab last (if desired)

## Step 2: Create Window Layout File

Create a `.psd1` file in `Modules/Window/Layouts/{MachineType}/`:

```
Modules/Window/Layouts/
├── PC/
│   └── MyNewWorkspace_PC.psd1
├── Laptop/
│   └── MyNewWorkspace_Laptop.psd1
└── Work/
    └── MyNewWorkspace_Work.psd1
```

Example layout file (`MyNewWorkspace_PC.psd1`):

```powershell
@{
    # Define which FancyZones layout to use per virtual desktop (1-based)
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "One"      # Desktop 1: Two zones (Left, Right)
                2 = "Eight"    # Desktop 2: Five zones
            }
        }
        # Secondary = @{
        #     VirtualDesktopLayouts = @{
        #         1 = "Seven"
        #     }
        # }
    }

    # Define where each window goes (DesktopNumber is 1-based)
    Layout = @(
        # ══════════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 1
        # ══════════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "Browser"
            WindowTitle   = "*"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Code"
            WindowTitle   = "*Visual Studio Code"
            DesktopNumber = 1
            Zone          = "Right"
            Monitor       = "Primary"
        }

        # ══════════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 2
        # ══════════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "Obsidian"
            WindowTitle   = "*Obsidian*"
            DesktopNumber = 2
            Zone          = "Left"
            Monitor       = "Primary"
        }
    )
}
```

### Window Rule Properties

| Property        | Description                                                                    | Example                            |
| --------------- | ------------------------------------------------------------------------------ | ---------------------------------- |
| `ProcessName`   | Process name, or the literal token `"Browser"` to match any configured browser | `"Browser"`, `"Code"`, `"devenv"`  |
| `WindowTitle`   | Title pattern (wildcards supported)                                            | `"*Visual Studio Code"`            |
| `DesktopNumber` | Virtual desktop number (**1-based**)                                           | `1`, `2`, `3`                      |
| `Zone`          | Zone name from `ZoneNameMappings`                                              | `"Left"`, `"Right"`, `"Top-Right"` |
| `Monitor`       | Monitor name                                                                   | `"Primary"`, `"Secondary"`         |

### Available Zone Names

Zone names come from `ZoneNameMappings` in `Configuration.psd1`, which maps each name to a zone index per layout - layouts and zone definitions in `custom-layouts.json` are freely editable (grid and canvas, any spacing), and `Test-FancyZonesConfiguration` verifies the mappings at every workspace open. Run `Visualize-Layouts -DisplayAvailableLayouts` to see all. The layouts shipped in this repo:

| Layout  | Zones                                                                     |
| ------- | ------------------------------------------------------------------------- |
| `Zero`  | Full, Fullscreen                                                          |
| `One`   | Left, Right                                                               |
| `Two`   | Left, Middle, Right                                                       |
| `Three` | Far-Left, Middle-Left, Middle-Right, Far-Right                            |
| `Four`  | Top-Left, Bottom-Left, Top-Right, Bottom-Right                            |
| `Five`  | Left, Right (different proportions)                                       |
| `Six`   | Left, Top-Right, Bottom-Right                                             |
| `Seven` | Left, Middle, Top-Right, Bottom-Right                                     |
| `Eight` | Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right                  |
| `Nine`  | Top-Left, Bottom-Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right |

## Step 3: Generate Layout Visualization

Add ASCII art visualization to the layout file:

```powershell
Visualize-Layouts -Layout "MyNewWorkspace_PC" -Update
```

This adds a visual comment block at the top:

```powershell
# ══════════════════════════════════════════════════════════════════════════════
# LAYOUT VISUALIZATION: MyNewWorkspace_PC
# ══════════════════════════════════════════════════════════════════════════════
#
# ┌─────────── VIRTUAL DESKTOP 1 ───────────┐
# │  PRIMARY MONITOR (Layout: One)          │
# ├─────────────────┬───────────────────────┤
# │    firefox      │        Code           │
# │  Mozilla Firefox│  Visual Studio Code   │
# └─────────────────┴───────────────────────┘
#
# ┌─────────── VIRTUAL DESKTOP 2 ───────────┐
# │  PRIMARY MONITOR (Layout: Eight)        │
# ├─────────┬─────────┬─────────────────────┤
# │         │         │                     │
# │ Obsidian│         │                     │
# └─────────┴─────────┴─────────────────────┘
# ══════════════════════════════════════════════════════════════════════════════
```

## Usage

After configuration:

```powershell
# Interactive workspace selection
# ([Enter] with no input opens Configuration.DefaultWorkspace - point it at
#  your new workspace to make it the one-keystroke default)
w

# Open specific workspace
w MyNewWorkspace

# Open workspace with specific project
w MyOrg OtherProject

# Open workspace, project, and run servers
w MyOrg OtherProject -RunApp
```

## Advanced: Dynamic Project Selection

For workspaces that prompt for project. The project menu is shown before anything launches, so `Project` scopes, `ProjectParameters` rows and the layout's `ProjectOverrides` all follow the choice; pressing Enter without a pick skips `Open-Project` instead of asking again:

```powershell
WorkspaceActions = @(
    @{ MyOrg = @(
            @{ Action = "Open-Project" }    # Empty parameters = prompts for selection
            @{ Action = "Open-DBeaver" }
            @{ Action = "Open-WhatsApp" }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyOrg" } }
            @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
        )
    }
)
```

## Complete Example

Adding a "Gaming" workspace:

```powershell
# 1. Define the workspace - the entry is what puts it in the menu, last in the list
WorkspaceActions = @(
    @{ WinuX = @( <#- ... -#> ) }
    @{ MyOrg = @( <#- ... -#> ) }

    @{ Gaming = @(
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("YouTube", "Twitch") } }
            @{ Action = "Open-Discord" }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Gaming" } }
            @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
        )
    }
)

# 2. Create layout file: Layouts/PC/Gaming_PC.psd1
@{
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{ 1 = "One" }
        }
    }
    Layout = @(
        @{
            ProcessName   = "Browser"
            WindowTitle   = "*YouTube*"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Discord"
            WindowTitle   = "*Discord*"
            DesktopNumber = 1
            Zone          = "Right"
            Monitor       = "Primary"
        }
    )
}

# 3. Generate visualization
Visualize-Layouts -Layout "Gaming_PC" -Update
```

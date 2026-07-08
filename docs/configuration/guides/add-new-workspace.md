# Add New Workspace

This guide shows how to create a new workspace for `Open-Workspace`.

## What is a Workspace?

A workspace is a collection of actions that set up a complete working environment:

- Open applications (browser, Obsidian, etc.)
- Open projects (VS Code, Visual Studio, terminals)
- Apply window layouts (position windows on screen)
- Run development servers

## Steps Overview

1. Add workspace to `Workspaces` list
2. Define workspace actions in `WorkspaceActions`
3. Create window layout file
4. Generate layout visualization

## Step 1: Add to Workspaces List

```powershell
Workspaces = @(
    "Example",
    "Fullscreen",
    "Empty",
    "Default",
    "WinuX",
    "MyNewWorkspace"    # ← Add here
)
```

## Step 2: Define Workspace Actions

In `WorkspaceActions`, specify what happens when opening:

```powershell
WorkspaceActions = @{
    MyNewWorkspace = @(
        @{ Action = "Open-Obsidian" }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "YouTube") } }
        @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
        @{ Action = "Open-DBeaver" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyNewWorkspace" } }
        @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
    )
}
```

### Available Actions

| Action                          | Description                   | Parameters                                                       |
| ------------------------------- | ----------------------------- | ---------------------------------------------------------------- |
| `Open-Obsidian`                 | Opens Obsidian vault          | None                                                             |
| `Open-Browser`                  | Opens browser with URL groups | `Groups = @("AI", "Tools")`, `Instances = N`, `Override = $true` |
| `Open-Project`                  | Opens a project               | `Project = "ProjectName"` or empty for prompt                    |
| `Open-VSCode`                   | Opens VS Code                 | `Folder = "FolderName"`                                          |
| `Open-VisualStudio`             | Opens Visual Studio           | `Solution = "SolutionName"`                                      |
| `Open-DBeaver`                  | Opens DBeaver                 | None                                                             |
| `Open-WhatsApp`                 | Opens WhatsApp                | None                                                             |
| `Open-Outlook`                  | Opens Outlook                 | None                                                             |
| `Open-Discord`                  | Opens Discord                 | None                                                             |
| `Open-Acrobat`                  | Opens PDFs                    | `Pdf = "GroupName"`                                              |
| `Open-DnD`                      | Opens D&D resources           | None                                                             |
| `Open-SecureBrowser`            | Opens Tor + VPN               | None                                                             |
| `Send-WakeOnLan`                | Wakes a machine               | None                                                             |
| `Set-WorkspaceWindowLayout`     | Applies window layout         | `WorkspaceName = "Name"`                                         |
| `Terminate-WindowsTerminalTabs` | Closes terminal tabs          | `OnlyCurrent = $true`                                            |
| `Test-PrivacyStatus`            | Tests VPN/Tor status          | None                                                             |
| `Return`                        | Stops processing              | None                                                             |

### Action Order Matters

Actions execute sequentially. Typically:

1. Open applications first
2. Apply window layout near the end (windows need to exist first)
3. Terminate calling tab last (if desired)

## Step 3: Create Window Layout File

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

Zone names depend on the layout. Run `Visualize-Layouts -DisplayAvailableLayouts` to see all:

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

## Step 4: Generate Layout Visualization

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
w

# Open specific workspace
w MyNewWorkspace

# Open workspace with specific project
w MyOrg OtherProject

# Open workspace, project, and run servers
w MyOrg OtherProject -RunApp
```

## Advanced: Dynamic Project Selection

For workspaces that prompt for project:

```powershell
WorkspaceActions = @{
    MyOrg = @(
        @{ Action = "Open-Project" }    # Empty parameters = prompts for selection
        @{ Action = "Open-DBeaver" }
        @{ Action = "Open-WhatsApp" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyOrg" } }
        @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
    )
}
```

## Complete Example

Adding a "Gaming" workspace:

```powershell
# 1. Add to list
Workspaces = @("WinuX", "MyOrg", "Gaming")

# 2. Define actions
WorkspaceActions = @{
    Gaming = @(
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("YouTube", "Twitch") } }
        @{ Action = "Open-Discord" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Gaming" } }
        @{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
    )
}

# 3. Create layout file: Layouts/PC/Gaming_PC.psd1
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

# 4. Generate visualization
Visualize-Layouts -Layout "Gaming_PC" -Update
```

# Configure Window Layout

This guide explains how to create and configure window layouts for the WinuX "tiling window manager" system.

## How Window Layouts Work

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        WINDOW LAYOUT SYSTEM                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. FancyZones (PowerToys)                                                  │
│     └─→ Defines zone layouts (saved in custom-layouts.json)                 │
│     └─→ Up to 10 layouts, arbitrary names (hotkeys 0-9 via LayoutNumbers)   │
│                                                                             │
│  2. Layout Files (.psd1)                                                    │
│     └─→ Define which windows go to which zones                              │
│     └─→ Organized by machine type: Layouts/PC/, Layouts/Laptop/             │
│                                                                             │
│  3. Set-WorkspaceWindowLayout                                               │
│     └─→ Reads layout file                                                   │
│     └─→ Normalizes browser windows to first tab only when they have >1 tab  │
│     └─→ Applies FancyZones layouts to monitors                              │
│     └─→ Moves windows to virtual desktops                                   │
│     └─→ Positions windows in zones using shared inset resize                │
│     └─→ Reapplies shared pre-snap resize to tracked windows                 │
│     └─→ Snaps windows using FancyZones                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Layout File Structure

Layout files are PowerShell data files (`.psd1`) with two main sections:

```powershell
@{
    # 1. Which FancyZones layout to use per monitor/desktop (1-based)
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "One"      # Desktop 1 uses "One" layout
                2 = "Eight"    # Desktop 2 uses "Eight" layout
            }
        }
        Secondary = @{
            VirtualDesktopLayouts = @{
                1 = "Seven"
            }
        }
    }

    # 2. Where each window goes (DesktopNumber is 1-based)
    Layout = @(
        @{
            ProcessName   = "firefox"
            WindowTitle   = "*Mozilla Firefox*"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
    )
}
```

## Available FancyZones Layouts

FancyZones layouts live in `Windows/FancyZones/custom-layouts.json` and are entirely editable: up to 10 layouts (arbitrary names, bound to hotkeys 0-9 via `LayoutNumbers` in `Configuration.psd1`), with freely chosen zones, row/column percentages, and any `spacing` value - both `grid` and `canvas` layout types work. Zone names for use in layout files come from `ZoneNameMappings`, which must be updated in lockstep when you add or reshape a layout; `Test-FancyZonesConfiguration` verifies all of it (layouts, `ZoneNameMappings`, `LayoutNumbers`, and `layout-hotkeys.json` sync) automatically at every workspace open.

View all layouts and their zones:

```powershell
Visualize-Layouts -DisplayAvailableLayouts
```

The layouts shipped in this repo are named `Zero` through `Nine`:

| Layout  | Zones                                                                     |
| ------- | ------------------------------------------------------------------------- |
| `Zero`  | Full (single zone, fullscreen)                                            |
| `One`   | Left, Right                                                               |
| `Two`   | Left, Middle, Right                                                       |
| `Three` | Far-Left, Middle-Left, Middle-Right, Far-Right                            |
| `Four`  | Top-Left, Bottom-Left, Top-Right, Bottom-Right                            |
| `Five`  | Left, Right (different proportions)                                       |
| `Six`   | Left, Top-Right, Bottom-Right                                             |
| `Seven` | Left, Middle, Top-Right, Bottom-Right                                     |
| `Eight` | Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right                  |
| `Nine`  | Top-Left, Bottom-Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right |

### Canvas Layouts

Besides `grid` layouts, FancyZones `canvas` layouts are fully supported: free-form rectangles drawn in the PowerToys FancyZones editor, saved with explicit X/Y/width/height in the layout's ref-width/ref-height space. A canvas zone's index is its position in the layout's `zones` array - map names to those indices in `ZoneNameMappings` exactly as for grid layouts. Canvas layouts ignore the `spacing` value. `Visualize-Layouts` renders them as a textual per-zone listing (e.g. `Zone 0 [Left]: x=0% y=0% w=50% h=100%`) rather than an ASCII grid.

## Creating a Layout File

### Step 1: Create the File

Create in the appropriate machine folder:

```
Modules/Window/Layouts/
├── PC/
│   └── MyWorkspace_PC.psd1       ← Create here for PC
├── Laptop/
│   └── MyWorkspace_Laptop.psd1   ← Create here for Laptop
└── Work/
    └── MyWorkspace_Work.psd1     ← Create here for Work
```

### Step 2: Define Monitor Configuration

```powershell
@{
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "One"    # Layout for desktop 1
            }
        }
    }
}
```

For multi-monitor:

```powershell
Monitors = @{
    Primary = @{
        VirtualDesktopLayouts = @{
            1 = "One"
            2 = "Eight"
        }
    }
    Secondary = @{
        VirtualDesktopLayouts = @{
            1 = "Seven"
            2 = "Four"
        }
    }
}
```

### Step 3: Define Window Rules

```powershell
Layout = @(
    @{
        ProcessName   = "Browser"          # "Browser" matches all configured browsers
        WindowTitle   = "*"                 # Title pattern (* = wildcard)
        DesktopNumber = 1                   # Virtual desktop (1-based)
        Zone          = "Left"              # Zone name
        Monitor       = "Primary"           # Monitor name
    }
    @{
        ProcessName   = "Code"              # No WindowTitle = catch-all (all VS Code windows)
        DesktopNumber = 1
        Zone          = "Right"
        Monitor       = "Primary"
    }
)
```

### Step 4: Generate Visualization

```powershell
Visualize-Layouts -Layout "MyWorkspace_PC" -Update
```

This adds an ASCII visualization at the top of the file.

## Finding Process Names and Window Titles

### Method 1: Get-ActiveWindowInfo

Focus the window and run:

```powershell
Get-ActiveWindowInfo
```

Output:

```
ProcessName : firefox
WindowTitle : GitHub - Mozilla Firefox
Handle      : 12345678
Position    : X=0, Y=0
Size        : 1920x1080
```

### Method 2: Continuous Mode

```powershell
Get-ActiveWindowInfo -Continuous
```

Updates live as you switch windows.

### Method 3: Task Manager

1. Open Task Manager (Ctrl+Shift+Esc)
2. Go to Details tab
3. Find the process name (e.g., `firefox.exe` → `firefox`)

## Window Title Patterns

Use wildcards for flexibility:

| Pattern               | Matches                           |
| --------------------- | --------------------------------- |
| `*Mozilla Firefox*`   | Any Firefox window                |
| `*Visual Studio Code` | VS Code (title ends with this)    |
| `*Obsidian*`          | Any Obsidian window               |
| `*- Visual Studio*`   | Visual Studio (not VS Code)       |
| `MyProject*`          | Windows starting with "MyProject" |

### Matching one window across browsers and states

`WindowTitle` is treated as a regular expression (it falls back to wildcard interpretation only when the value is not valid regex), so a single entry can target a window whose title changes with the browser or the app's state. The Server layout uses this to place a project's API/Swagger tab no matter which browser opened it or whether the backend is running:

```powershell
@{
    ProcessName   = "Browser"
    WindowTitle   = "(.*Problem loading page.*|.*\blocalhost\b.*|.*Swagger UI.*|.*\bAsseto\b.*)"
    DesktopNumber = 2
    Zone          = "Left"
    Monitor       = "Primary"
}
```

| Title fragment         | When it appears                                                     |
| ---------------------- | ------------------------------------------------------------------- |
| `Swagger UI`           | Backend up - the rendered Swagger page's own title (any browser)    |
| `Problem loading page` | Backend down in Firefox (its error-page title)                      |
| `localhost`            | Backend down in Chromium browsers (Chrome/Edge/Brave show the host) |
| `Asseto`, ...          | A backend that customizes its Swagger/page title per project        |

This keeps the zone filled whether or not the API is running, and across Firefox and all Chromium browsers - `localhost` is locale-independent, while `Problem loading page` is Firefox's English title.

## Multi-Virtual-Desktop Layouts

```powershell
@{
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "One"      # Desktop 1: Code on left, Browser on right
                2 = "Eight"    # Desktop 2: Complex layout for monitoring
            }
        }
    }

    Layout = @(
        # ══════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 1
        # ══════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "Code"
            WindowTitle   = "*Visual Studio Code"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Browser"
            WindowTitle   = "*"
            DesktopNumber = 1
            Zone          = "Right"
            Monitor       = "Primary"
        }

        # ══════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 2
        # ══════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "Obsidian"
            WindowTitle   = "*Obsidian*"
            DesktopNumber = 2
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "dbeaver"
            WindowTitle   = "*DBeaver*"
            DesktopNumber = 2
            Zone          = "Top-Right"
            Monitor       = "Primary"
        }
    )
}
```

## Complete Example: Development Workspace

```powershell
# Layouts/PC/Development_PC.psd1

@{
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "Seven"    # Coding: Left (VS), Middle (VSCode), Right stack (Browser/Tools)
                2 = "One"      # Reference: Obsidian | Browser
            }
        }
    }

    Layout = @(
        # ══════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 1 - Main Development
        # ══════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "devenv"
            WindowTitle   = "*- Visual Studio*"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Code"
            WindowTitle   = "*Visual Studio Code"
            DesktopNumber = 1
            Zone          = "Middle"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Browser"
            WindowTitle   = "*"
            DesktopNumber = 1
            Zone          = "Top-Right"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "dbeaver"
            WindowTitle   = "*DBeaver*"
            DesktopNumber = 1
            Zone          = "Bottom-Right"
            Monitor       = "Primary"
        }

        # ══════════════════════════════════════════════════════════════════
        # VIRTUAL DESKTOP 2 - Reference
        # ══════════════════════════════════════════════════════════════════
        @{
            ProcessName   = "Obsidian"
            WindowTitle   = "*Obsidian*"
            DesktopNumber = 2
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Browser"
            WindowTitle   = "*Documentation*"
            DesktopNumber = 2
            Zone          = "Right"
            Monitor       = "Primary"
        }
    )
}
```

## Applying Layouts

Layouts are applied via workspace actions:

```powershell
WorkspaceActions = @{
    Development = @(
        # ... open apps first ...
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Development" } }
    )
}
```

Or manually:

```powershell
Set-WorkspaceWindowLayout -WorkspaceName "Development"

# Verbose diagnostic output
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName "Development" }
```

During application, windows are first positioned inside their target zones using a shared inset-resize calculation. Right before snap, `Resize-PositionedWindows` reapplies that same geometry so the initial snap attempt and any later snap recovery use the exact same bounds. How much is trimmed off each side comes from `SnapInsetPercent` (default `0.05`), read through `Get-WindowInsetPercent` - one value shared by every placement path.

Windows opened for the first time are also normalized by `Resize-Windows` with no explicit `-Percent`, so their scale comes from `ResizeWindowsPercent` (default `70`). Both sections are documented under [Display-Aware Window Sizing](../configuration-reference.md#display-aware-window-sizing), where a `SmallDisplay` row lets a laptop-class panel shrink windows less than a wide monitor does.

## Running a Machine on a Different Monitor Setup

A machine's layouts encode its monitors: zone geometry, how many virtual desktops, which windows land on `Secondary`. Move that machine to a different setup - a desktop taken somewhere without its usual monitors, one screen instead of two - and its layouts describe hardware that is not there. Rewriting them means losing the set you want back later.

`LayoutMachineTypeOverrides` (in `Configuration.psd1`, or `Configuration.local.psd1` in a fork) redirects a machine's **window-arrangement** settings - its layout folder and its `Reset-Windows` profile - to a different machine type, leaving the machine's own layout set untouched:

```powershell
LayoutMachineTypeOverrides = @{
    PC     = "Temp"   # PC reads Layouts/Temp/<Workspace>_Temp.psd1
    Laptop = ""       # "" = no override, use this machine's own layout set
    Work   = ""
    Test   = ""
}
```

Workflow:

1. Author a layout for each workspace you open in `Modules/Window/Layouts/Temp/`, named `<WorkspaceName>_Temp.psd1` - same structure as any other layout file, with geometry matching the new setup. `Add-WindowLayout -WorkspaceName MyWorkspace -MachineType Temp` scaffolds one and creates the folder on first use; copying an `Example_<MachineType>.psd1` in as `Example_Temp.psd1` gives a zone reference you can inspect with `Visualize-Layouts -Layout "Example_Temp"`.
2. Add a `ResetAllWindowsDefaults` entry under the same name if the new setup needs different reset targeting - e.g. `Temp = @{ VirtualDesktop = 1; Monitor = "" }` for a single screen, where the machine's usual "consolidate onto monitor 2" no longer means anything. Without an entry it falls back to `Default`.
3. Set the override for the machine (e.g. `PC = "Temp"`) and open workspaces as usual - nothing about the commands changes.
4. Back on the original setup, set the entry to `""`. The machine's real layouts return exactly as they were.

Notes:

- Layouts and `ResetAllWindowsDefaults` both follow the override, because both describe monitors. Everything else keyed by machine type (base paths, symbolic links, wallpapers, themes, taskbar) keeps using the real machine type.
- The override wins over `SmallDisplayMachineType`, so a deliberate choice is not overruled when the temporary screen happens to be small.
- There is no silent fallback: a workspace with no layout file in the redirected set is reported, not quietly laid out with the machine's own (wrong-monitor) geometry.

## Troubleshooting

### Window Not Being Positioned

1. Check process name matches exactly (case-sensitive)
2. Verify window title pattern matches
3. Use `Get-ActiveWindowInfo` to get correct values
4. Use `Set-LogLevel Verbose` to see what's happening

### Layout Not Applied

1. Ensure FancyZones is running: `Start-FancyZones`
2. Verify layout name exists in `ZoneNameMappings`
3. Check monitor name matches (`Primary`, `Secondary`)
4. Run `Test-FancyZonesConfiguration` to catch drift between `custom-layouts.json`, `ZoneNameMappings`, `LayoutNumbers`, and `layout-hotkeys.json` (it also runs automatically at every workspace open)

### "No layout configuration found for workspace"

The workspace has no layout file for the layout set currently in effect. That set is not always the machine type: check `LayoutMachineTypeOverrides` for the machine (a non-empty value redirects to `Layouts/<value>/`) and `SmallDisplayMachineType` (a primary display up to 3000px wide switches sets). The warning names the set it searched and the exact file path it expected - create that file, or clear the override entry to go back to the machine's own layout set. `Get-LayoutMachineType` reports the same answer on its own if you want to check which set is active before running anything.

### Validate Layout

```powershell
Visualize-Layouts -Layout "MyWorkspace_PC"
```

Shows validation errors and warnings.

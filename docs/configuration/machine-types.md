# Machine Types

WinuX supports **multiple machines from a single configuration** through the machine type system. It ships with a single machine type - `Test`, the minimal, VM-friendly working profile - and you can define as many more as you like (the examples below add `PC`, `Laptop`, and `Work`). Each machine gets its own settings while sharing most of the configuration.

## Supported Machine Types

| Machine Type | Typical Use Case             | Example Hostname |
| ------------ | ---------------------------- | ---------------- |
| `PC`         | Desktop/gaming machine       | `DESKTOP-GAMING`       |
| `Laptop`     | Portable development machine | `LAPTOP-PERSONAL`   |
| `Work`       | Company/office machine       | `WORKSTATION-01`        |
| `Test`       | Testing/virtual machine      | `Test`           |

> [!NOTE]
> The table above is illustrative. WinuX ships with just `Test` defined; `PC`, `Laptop`, and `Work` are shown as examples of types you can add. Replace the hostnames with your own machine names in the `HostnameToMachineType` mapping.

## How Machine Type Detection Works

```
┌──────────────────────────────────────────────────────────────────────┐
│                        MACHINE TYPE DETECTION                        │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Read hostname from system                                        │
│     └─→ $env:COMPUTERNAME (e.g., "DESKTOP-GAMING")                   │
│                                                                      │
│  2. Look up in HostnameToMachineType mapping                         │
│     └─→ "DESKTOP-GAMING" → "PC"                                      │
│     └─→ "LAPTOP-PERSONAL" → "Laptop"                                 │
│     └─→ "WORKSTATION-01" → "Work"                                    │
│                                                                      │
│  3. If not found, prompt user interactively                          │
│     └─→ Lists valid types and asks for selection                     │
│                                                                      │
│  4. Set $global:MachineType                                          │
│     └─→ Used for placeholder expansion                               │
│     └─→ Used throughout all configuration                            │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Configuration Sections

### Valid Machine Types

Defines which machine types are allowed:

```powershell
ValidMachineTypes = @("Test")   # add your own, e.g. "PC", "Laptop", "Work"
```

### Hostname to Machine Type Mapping

Maps Windows hostnames to machine types:

```powershell
HostnameToMachineType = @{
    "DESKTOP-GAMING"     = "PC"
    "LAPTOP-PERSONAL" = "Laptop"
    "WORKSTATION-01"      = "Work"
    "Test"         = "Test"
}
```

### Default Machine Type

Fallback when hostname isn't in the mapping:

```powershell
DefaultMachineType = "Test"
```

> [!NOTE]
> When the hostname is not found in the mapping, `DetermineMachineType` does **not** automatically use `DefaultMachineType`. Instead, it **prompts the user interactively** - listing valid machine types and asking for manual selection.

### Laptop Chassis Types

Used for detecting laptop hardware:

```powershell
LaptopChassisTypes = @(8, 9, 10, 11, 14, 30, 31, 32)
```

- `8` Portable, `9` Laptop, `10` Notebook, `11` Handheld
- `14` Sub-Notebook, `30` Tablet, `31` Convertible, `32` Detachable

## What Changes Per Machine Type

### 1. Base Paths (`{Dev}` and `{User}` Placeholders)

```powershell
BasePaths = @{
    PC     = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Laptop = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Work   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

> [!NOTE]
> In this example, all machines use the same paths. You can customize per machine if your directory structure differs (e.g., `PC` uses `E:\Development\GitHub`).

### 2. System Theme

```powershell
Themes = @{
    "PC"     = "Dark"
    "Laptop" = "Dark"
    "Work"   = "Dark"
    "Test"   = "Dark"
}
```

### 3. Wallpaper Settings

```powershell
# Dark theme wallpapers
WallpaperDarkSettings = @{
    "PC" = @{
        Monitors = @(                              # Multi-monitor setup
            @{ File = "Space1.jpg"; Style = "Stretch" }
            @{ File = "Space2.jpg"; Style = "Stretch" }
        )
    }
    "Laptop"  = @{ File = "BlackHole.png"; Style = "Fill" }
    "Work"    = @{ File = "BlackHole.png"; Style = "Fill" }
    "Test"    = @{ File = "Black.jpg"; Style = "Fill" }
    "Default" = @{ File = "Black.jpg"; Style = "Fill" }
}

# Light theme wallpapers
WallpaperLightSettings = @{
    "PC" = @{
        Monitors = @(
            @{ File = "AbstractGeometry1.jpg"; Style = "Fill" }
            @{ File = "AbstractGeometry2.jpg"; Style = "Fill" }
        )
    }
    "Laptop"  = @{ File = "BlackWhite1.jpg"; Style = "Fill" }
    "Work"    = @{ File = "BlackWhite1.jpg"; Style = "Fill" }
    "Test"    = @{ File = "White.png"; Style = "Fill" }
    "Default" = @{ File = "White.png"; Style = "Fill" }
}
```

### 4. Configuration Files via `{MachineType}` Placeholder

Many dotfiles are machine-specific using the `{MachineType}` placeholder:

```powershell
SymbolicLinks = @{
    # FastFetch configuration per machine
    FastFetch = @{
        Configuration = @{
            Path   = "{User}\.config\fastfetch\config.jsonc"
            Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
        }
        Logo = @{
            Path   = "{User}\.config\fastfetch\FastFetchLogo_{MachineType}.txt"
            Target = "{RepoRoot}\FastFetch\Windows\FastFetchLogo_{MachineType}.txt"
        }
    }

    # Oh-My-Posh theme per machine
    OhMyPosh = @{
        Path   = "{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"
        Target = "{RepoRoot}\Windows\Oh-My-Posh\WinuX_{MachineType}.omp.json"
    }

    # Windows Terminal settings per machine
    WindowsTerminal = @{
        Settings = @{
            Path   = "{User}\AppData\Local\...\settings.json"
            Target = "{RepoRoot}\Windows\WindowsTerminal\settings_{MachineType}.json"
        }
    }

    # A fork payload per machine (illustrative - add your own payloads the same way)
    Rainmeter = @{
        MainConfig = @{
            Path   = "{AppData}\Rainmeter\Rainmeter.ini"
            Target = "{RepoRoot}\Windows\Rainmeter\Rainmeter_{MachineType}.ini"
        }
    }
}
```

### 5. Window Layouts (FancyZones)

Layout files are organized by machine type:

```
Layouts/
├── PC/
│   ├── Default_PC.psd1
│   ├── WinuX_PC.psd1
│   ├── MyOrg_PC.psd1
│   └── ...
├── Laptop/
│   ├── Default_Laptop.psd1
│   ├── WinuX_Laptop.psd1
│   └── ...
├── Work/
│   └── ...
└── Test/
    └── ...
```

## Checking Current Machine Type

```powershell
# View current machine type
$global:MachineType
# Output: PC

# View hostname
$env:COMPUTERNAME
# Output: DESKTOP-GAMING

# View base paths for current machine
$global:Configuration.BasePaths[$global:MachineType]
# Output: @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
```

## Adding a New Machine

To add a new machine type (e.g., a new work laptop):

### Step 1: Add Hostname Mapping

```powershell
HostnameToMachineType = @{
    "DESKTOP-GAMING"        = "PC"
    "LAPTOP-PERSONAL"    = "Laptop"
    "WORKSTATION-01"         = "Work"
    "Test"            = "Test"
    "NewWorkLaptop"   = "Work"   # ← New machine, maps to existing type
}
```

### Step 2: (Optional) Add New Machine Type

If you need a completely new type:

```powershell
# Add to valid types
ValidMachineTypes = @("PC", "Laptop", "Work", "Test", "Server")

# Add hostname mapping
HostnameToMachineType = @{
    ...
    "HomeServer" = "Server"
}

# Add base paths
BasePaths = @{
    ...
    Server = @{ Dev = "/home/you/dev"; User = "/home/you" }
}

# Add theme
Themes = @{
    ...
    "Server" = "Dark"
}

# Add wallpaper settings
WallpaperDarkSettings = @{
    ...
    "Server" = @{ File = "Server.jpg"; Style = "Fill" }
}
```

### Step 3: Create Machine-Specific Config Files

For a new type, create the needed config files:

```powershell
# FastFetch
FastFetch/Windows/config_Server.jsonc
FastFetch/Windows/FastFetchLogo_Server.txt

# Oh-My-Posh
Windows/Oh-My-Posh/WinuX_Server.omp.json

# Windows Terminal
Windows/WindowsTerminal/settings_Server.json

# Layouts
Windows/PowerShell/Modules/Window/Layouts/Server/
```

### Step 4: Rename the Machine (If Needed)

```powershell
# Use WinuX function
Rename-Machine

# Or manually
Rename-Computer -NewName "NewHostname" -Restart
```

## Taskbar Configuration

One `TaskbarConfiguration` list serves every machine; each row's `Machine` scope decides where it
pins. `Test-MachineTypeScope` matches the scope against the current machine type exactly like the
app CSVs' `Machine` column: `All` pins everywhere, `PC/Work` only on PC or Work, and a row with no
`Machine` key (or a blank one) defaults to `All`. Every type you use must exist in
`ValidMachineTypes`, or it is reported as an unknown token.

```powershell
TaskbarConfiguration = @(
    @{ Name = "WindowsTerminal"; Type = "AUMID"; Value = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"; Machine = "All" }
    @{ Name = "Obsidian";        Type = "AUMID"; Value = "md.obsidian";                                 Machine = "All" }
    @{ Name = "VSCode";          Type = "AUMID"; Value = "Microsoft.VisualStudioCode";                  Machine = "PC/Work" }
    @{ Name = "DBeaver";         Type = "Path";  Value = "{User}\AppData\Local\DBeaver\dbeaver.exe";    Machine = "PC" }
)
```

Keep your real, machine-tagged list in `Configuration.local.psd1` (it replaces the base array
wholesale on merge). `Configure-Taskbar` states which machine type it is configuring for, then
writes the generated layout per-machine to `TaskbarLayoutFile`
(`C:\ProgramData\provisioning\taskbar_layout.xml`) — not versioned in the repo, no symlink.

### Window Layouts

Layout files are organized by machine type:

```
Modules/Window/Layouts/
├── PC/
│   ├── WinuX_PC.psd1
│   ├── MyOrg_PC.psd1
│   └── ...
├── Laptop/
│   ├── WinuX_Laptop.psd1
│   └── ...
└── Work/
    ├── MyOrg_Work.psd1
    └── ...
```

### Configuration Files (via Placeholders)

```powershell
FastFetch = @{
    Configuration = @{
        Path   = "{User}\.config\fastfetch\config.jsonc"
        Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
    }
}
```

This creates machine-specific symlinks:

- PC → `config_PC.jsonc`
- Laptop → `config_Laptop.jsonc`
- Work → `config_Work.jsonc`

## Checking Machine Type

```powershell
# Current machine type
$MachineType

# All machine-specific paths
$MachineSpecificPaths

# Force redetermination
DetermineMachineType
```

## Adding a New Machine

See [Add New Machine](guides/add-new-machine.md) for step-by-step instructions.

## Application Filtering

Apps can be installed only on specific machines via CSV files:

```csv
App,Version,Scope,Interactive,Source,Machine
PostgreSQL.PostgreSQL.17,Latest,machine,no,winget,Work
VirtualBox,7.1.12,d,n,w,PC/Laptop
Firefox,Latest,d,n,w,All
```

- `All` - Install on all machines
- `PC` - Only on PC
- `PC/Laptop` - On PC and Laptop
- `Work` - Only on Work machine

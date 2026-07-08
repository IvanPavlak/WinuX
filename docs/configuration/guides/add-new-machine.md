# Add New Machine

This guide walks you through adding support for a new machine type to WinuX.

## Steps Overview

1. Add hostname → machine type mapping
2. Add base paths
3. Add theme setting
4. Add wallpaper settings
5. (Optional) Add taskbar configuration
6. Create window layout files

## Step 1: Add Hostname Mapping

In `Configuration.psd1`, add your machine's hostname:

```powershell
HostnameToMachineType = @{
    "DESKTOP-GAMING"     = "PC"
    "LAPTOP-PERSONAL" = "Laptop"
    "WORKSTATION-01"      = "Work"
    "Test"         = "Test"
    "Gaming-PC"    = "Gaming"      # ← Add new mapping
}
```

If using a new machine type, add it to valid types. The shipped configuration starts with only
`Test` - add your new type alongside it:

```powershell
ValidMachineTypes = @("Test", "Gaming")
```

> [!NOTE]
> The `PC`, `Laptop`, and `Work` entries shown in the examples below are illustrative
> user-added types - a fresh `Configuration.psd1` contains only `Test`.

## Step 2: Add Base Paths

Define the development and user paths:

```powershell
BasePaths = @{
    PC     = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Laptop = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Work   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Gaming = @{ Dev = "D:\Dev";                    User = "C:\Users\You" }  # ← Add new
}
```

## Step 3: Add Theme Setting

```powershell
Themes = @{
    "PC"     = "Dark"
    "Laptop" = "Dark"
    "Work"   = "Dark"
    "Gaming" = "Dark"              # ← Add new
}
```

## Step 4: Add Wallpaper Settings

For single monitor:

```powershell
WallpaperDarkSettings = @{
    "PC"      = @{ ... }
    "Gaming"  = @{ File = "Gaming.jpg"; Style = "Fill" }  # ← Add new
}

WallpaperLightSettings = @{
    "PC"      = @{ ... }
    "Gaming"  = @{ File = "GamingLight.jpg"; Style = "Fill" }  # ← Add new
}
```

For multi-monitor:

```powershell
WallpaperDarkSettings = @{
    "Gaming" = @{
        Monitors = @(
            @{ File = "Gaming1.jpg"; Style = "Stretch" }
            @{ File = "Gaming2.jpg"; Style = "Stretch" }
        )
    }
}
```

## Step 5: (Optional) Taskbar Configuration

If you want different taskbar pins:

```powershell
# The default TaskbarConfiguration applies to all machines
# For machine-specific configs, you'd modify the function
```

## Step 6: Create Window Layout Files

Create a folder and layout files:

```
Modules/Window/Layouts/Gaming/
├── Default_Gaming.psd1
├── WinuX_Gaming.psd1
└── MyOrg_Gaming.psd1
```

Example layout file (`Default_Gaming.psd1`):

```powershell
@{
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "One"    # Use "One" layout (Left/Right zones)
            }
        }
    }
    Layout = @(
        # VIRTUAL DESKTOP 1
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
    )
}
```

Then generate visualization:

```powershell
Visualize-Layouts -Layout "Default_Gaming" -Update
```

## Step 7: Create Machine-Specific Config Files

For configs that vary by machine, create new files:

```
FastFetch/Windows/
├── config_PC.jsonc
├── config_Laptop.jsonc
├── config_Work.jsonc
└── config_Gaming.jsonc       # ← Create new

Oh-My-Posh/
├── Custom_PC.omp.json
├── Custom_Laptop.omp.json
├── Custom_Work.omp.json
└── Custom_Gaming.omp.json    # ← Create new

WindowsTerminal/
├── settings_PC.json
├── settings_Laptop.json
├── settings_Work.json
└── settings_Gaming.json      # ← Create new
```

## Verification

1. Set your hostname:

    ```powershell
    Rename-Computer -NewName "Gaming-PC" -Restart
    ```

2. After restart, verify detection:

    ```powershell
    $MachineType  # Should output "Gaming"
    ```

3. Run Bootstrap to apply configuration:
    ```powershell
    Bootstrap
    ```

## Complete Example

Here's everything together for a new "Gaming" machine:

```powershell
# In Configuration.psd1

ValidMachineTypes = @("PC", "Laptop", "Work", "Test", "Gaming")

HostnameToMachineType = @{
    "DESKTOP-GAMING"     = "PC"
    "LAPTOP-PERSONAL" = "Laptop"
    "WORKSTATION-01"      = "Work"
    "Test"         = "Test"
    "Gaming-PC"    = "Gaming"
}

BasePaths = @{
    PC     = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Laptop = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Work   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Gaming = @{ Dev = "D:\Dev";                    User = "C:\Users\You" }
}

Themes = @{
    "PC"     = "Dark"
    "Laptop" = "Dark"
    "Work"   = "Dark"
    "Gaming" = "Dark"
}

WallpaperDarkSettings = @{
    "PC"      = @{ ... }
    "Laptop"  = @{ ... }
    "Work"    = @{ ... }
    "Gaming"  = @{ File = "Gaming.jpg"; Style = "Fill" }
}
```

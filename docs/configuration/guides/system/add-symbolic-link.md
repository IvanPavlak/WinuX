# Add Symbolic Link

This guide shows how to add a new symbolic link to WinuX for dotfile synchronization.

## What Are Symbolic Links?

Symbolic links (symlinks) point from a system location to a file in your WinuX repository:

```
System Location (Path)              WinuX Repository (Target)
─────────────────────────          ─────────────────────────────
~\.gitconfig                   →   WinuX\Git\.gitconfig
~\.config\fastfetch\config.jsonc → WinuX\FastFetch\config_PC.jsonc
```

Changes to the file in WinuX are automatically reflected everywhere.

## How Symbolic Links Are Defined

In `Configuration.psd1` under `PathTemplates.SymbolicLinks`:

```powershell
SymbolicLinks = @{
    Git = @{
        Path   = "{User}\.gitconfig"              # Where symlink is created
        Target = "{RepoRoot}\Git\.gitconfig"  # What it points to (source)
    }
}
```

## Adding a Simple Symlink

### Step 1: Add Entry to Configuration

```powershell
SymbolicLinks = @{
    # Existing symlinks...

    MyApp = @{
        Path   = "{User}\AppData\Roaming\MyApp\config.json"
        Target = "{RepoRoot}\MyApp\config.json"
    }
}
```

### Step 2: Create the Target File

Create the actual file in your WinuX repository:

```
WinuX/
└── MyApp/
    └── config.json    ← Create this file
```

### Step 3: Run SymbolicLinkMaker

```powershell
SymbolicLinkMaker
```

Or run full Bootstrap which includes it.

## Adding Nested Symlinks

For multiple files in the same app:

```powershell
SymbolicLinks = @{
    PowerToys = @{
        Settings = @{
            Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\settings.json"
            Target = "{RepoRoot}\Windows\FancyZones\settings.json"
        }
        CustomLayouts = @{
            Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\custom-layouts.json"
            Target = "{RepoRoot}\Windows\FancyZones\custom-layouts.json"
        }
        LayoutHotkeys = @{
            Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\layout-hotkeys.json"
            Target = "{RepoRoot}\Windows\FancyZones\layout-hotkeys.json"
        }
    }
}
```

## Machine-Specific Symlinks

Use `{MachineType}` placeholder for machine-specific configs:

```powershell
SymbolicLinks = @{
    FastFetch = @{
        Configuration = @{
            Path   = "{User}\.config\fastfetch\config.jsonc"
            Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
        }
    }
}
```

This creates:

- On PC: Links to `config_PC.jsonc`
- On Laptop: Links to `config_Laptop.jsonc`
- On Work: Links to `config_Work.jsonc`

Create the corresponding files:

```
WinuX/FastFetch/Windows/
├── config_PC.jsonc
├── config_Laptop.jsonc
└── config_Work.jsonc
```

## WSL Symlinks

For WSL paths, use forward slashes - they're auto-detected:

```powershell
SymbolicLinks = @{
    WSLSSH = @{
        Path   = "/home/you/.ssh/config"                    # WSL path
        Target = "{RepoRoot}/Server/.ssh/config"         # Auto-converted
    }
    WSLFastFetch = @{
        Configuration = @{
            Path   = "/home/you/fastfetch/config.jsonc"
            Target = "{RepoRoot}/FastFetch/Windows/WSL/config_WSL_{MachineType}.jsonc"
        }
    }
}
```

WSL symlinks use `wsl ln -s` instead of Windows `New-Item`.

## Available Placeholders

| Placeholder      | Example Value                               |
| ---------------- | ------------------------------------------- |
| `{User}`         | `C:\Users\You`                             |
| `{Dev}`          | `C:\Users\You\Development\GitHub`                 |
| `{AppData}`      | `C:\Users\You\AppData\Roaming`             |
| `{RepoRoot}` | `C:\Users\You\Development\GitHub\WinuX` |
| `{MachineType}`  | `PC`, `Laptop`, `Work`                      |

## Common Symlink Locations

| Application        | Typical Path                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| Git config         | `{User}\.gitconfig`                                                                              |
| SSH config         | `{User}\.ssh\config`                                                                             |
| PowerShell profile | `{User}\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`                                   |
| Windows Terminal   | `{User}\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` |
| VS Code            | `{AppData}\Code\User\settings.json`                                                              |
| Oh My Posh         | `{User}\AppData\Local\Programs\oh-my-posh\themes\*.omp.json`                                     |
| PowerToys          | `{User}\AppData\Local\Microsoft\PowerToys\*`                                                     |

## Prerequisites

- **Developer Mode** must be enabled (Bootstrap does this automatically)
- **Administrator privileges** are NOT required if Developer Mode is on
- For WSL symlinks, WSL must be installed

Enable Developer Mode manually:

```powershell
Enable-DeveloperMode
```

## Troubleshooting

### "A required privilege is not held by the client"

Developer Mode isn't enabled:

```powershell
Enable-DeveloperMode
# Or: Settings → Privacy & security → For developers → Developer Mode
```

### Symlink Already Exists

`SymbolicLinkMaker` handles existing items:

- If a symlink or regular file already exists at the path: it is removed (no backup is made) and the link is recreated
- If the entry's target does not exist: the entry is skipped with a warning and the existing file is left untouched

### WSL Symlink Failed

Ensure WSL is installed and the target path exists:

```powershell
wsl -l -v                           # Check WSL is installed
wsl ls -la /path/to/check           # Verify path exists
```

## Complete Example

Adding VS Code extensions sync:

```powershell
# 1. Add to SymbolicLinks
SymbolicLinks = @{
    VSCode = @{
        Settings = @{
            Path   = "{AppData}\Code\User\settings.json"
            Target = "{RepoRoot}\Windows\VSCode\settings.json"
        }
        Keybindings = @{
            Path   = "{AppData}\Code\User\keybindings.json"
            Target = "{RepoRoot}\Windows\VSCode\keybindings.json"
        }
        Snippets = @{
            Path   = "{AppData}\Code\User\snippets"
            Target = "{RepoRoot}\Windows\VSCode\snippets"
        }
    }
}

# 2. Create files/folders in WinuX
# WinuX/Windows/VSCode/
# ├── settings.json
# ├── keybindings.json
# └── snippets/

# 3. Apply
SymbolicLinkMaker
```

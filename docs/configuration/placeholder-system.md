# Placeholder System

WinuX uses a powerful placeholder system that enables **one configuration file to work across multiple machines** with different directory structures.

## Available Placeholders

| Placeholder      | Description              | Example Value                               |
| ---------------- | ------------------------ | ------------------------------------------- |
| `{Dev}`          | Development base path    | `C:\Users\You\Development\GitHub`                 |
| `{User}`         | User profile path        | `C:\Users\You`                             |
| `{MachineType}`  | Current machine type     | `PC`, `Laptop`, `Work`, `Test`              |
| `{RepoRoot}` | WinuX repository root | `C:\Users\You\Development\GitHub\WinuX` |
| `{AppData}`      | User's AppData\Roaming   | `C:\Users\You\AppData\Roaming`             |

## How Placeholders Work

```
┌─────────────────────────────────────────────────────────────────┐
│  Configuration.psd1 (Template)                                  │
│  ───────────────────────────────                                │
│  Root = "{Dev}\MyProject"                                       │
│  Config = "{RepoRoot}\MyProject\config_{MachineType}.json"      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Load-PathConfiguration (at startup)                            │
│  ───────────────────────────────────                            │
│  1. Detect MachineType from hostname                            │
│  2. Get BasePaths for that machine                              │
│  3. Call Expand-ConfigPaths to replace placeholders             │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│  PC Machine             │   │  Laptop Machine         │
│  ─────────────          │   │  ──────────────         │
│  {Dev} → E:\Dev         │   │  {Dev} → C:\Users\Dev   │
│  {User} → C:\Users\John │   │  {User} → C:\Users\John │
│  {MachineType} → PC     │   │  {MachineType} → Laptop │
└─────────────────────────┘   └─────────────────────────┘
```

## Step-by-Step: How Expansion Works

### Step 1: Define Base Paths Per Machine

```powershell
# In Configuration.psd1
BasePaths = @{
    PC     = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Laptop = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Work   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test   = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

### Step 2: Write Paths Using Placeholders

```powershell
PathTemplates = @{
    Projects = @{
        MyApp = @{
            Root     = "{Dev}\MyApp"
            Settings = "{User}\AppData\Local\MyApp"
            Config   = "{RepoRoot}\MyApp\config_{MachineType}.json"
        }
    }
}
```

### Step 3: Automatic Expansion at Runtime

When `Expand-ConfigPaths` runs on a **PC** machine:

| Template                                         | Expanded Value                           |
| ------------------------------------------------ | ---------------------------------------- |
| `{Dev}\MyApp`                             | `C:\Users\You\Development\GitHub\MyApp` |
| `{User}\AppData\Local\MyApp`                     | `C:\Users\You\AppData\Local\MyApp`      |
| `{RepoRoot}\MyApp\config_{MachineType}.json` | `C:\...\WinuX\MyApp\config_PC.json`   |

## Placeholder Reference

### `{Dev}` - Development Directory

The root of your development/projects folder.

```powershell
# Configuration
BasePaths = @{
    PC = @{ Dev = "C:\Users\You\Development\GitHub" }
}

# Usage
Projects = @{
    Self = @{ Root = "{RepoRoot}" }
}

# Result
"C:\Users\You\Development\GitHub\WinuX"
```

### `{User}` - User Profile

The Windows user profile directory.

```powershell
# Configuration
BasePaths = @{
    PC = @{ User = "C:\Users\You" }
}

# Usage
SymbolicLinks = @{
    Git = @{
        Path = "{User}\.gitconfig"
    }
}

# Result
"C:\Users\You\.gitconfig"
```

### `{MachineType}` - Current Machine

Dynamically replaced with PC, Laptop, Work, or Test.

```powershell
# Usage - Machine-specific config files
FastFetch = @{
    Configuration = @{
        Target = "{RepoRoot}\FastFetch\config_{MachineType}.jsonc"
    }
}

# Result on PC:    "...\FastFetch\config_PC.jsonc"
# Result on Laptop: "...\FastFetch\config_Laptop.jsonc"
```

### `{RepoRoot}` - Repository Root

Automatically resolved to the WinuX repository location.

```powershell
# Usage
SymbolicLinks = @{
    Git = @{
        Target = "{RepoRoot}\Git\.gitconfig"
    }
}

# Result
"C:\Users\You\Development\GitHub\WinuX\Git\.gitconfig"
```

### `{AppData}` - Application Data

User's AppData\Roaming folder.

```powershell
# Usage
SymbolicLinks = @{
    VSCode = @{
        Path = "{AppData}\Code\User\settings.json"
    }
}

# Result
"C:\Users\You\AppData\Roaming\Code\User\settings.json"
```

## Common Usage Patterns

### Pattern 1: Project Paths

```powershell
Projects = @{
    MyProject = @{
        Root     = "{Dev}\MyProject"
        Solution = "{Dev}\MyProject\MyProject.sln"
        Api      = "{Dev}\MyProject\src\Api"
        Ui       = "{Dev}\MyProject\ui"
    }
}
```

### Pattern 2: Symbolic Links (Configuration Files)

```powershell
SymbolicLinks = @{
    # Simple symlink
    Git = @{
        Path   = "{User}\.gitconfig"           # Created here (symlink)
        Target = "{RepoRoot}\Git\.gitconfig"  # Points to this (real file)
    }

    # Machine-specific symlink
    OhMyPosh = @{
        Path   = "{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"
        Target = "{RepoRoot}\Windows\Oh-My-Posh\WinuX_{MachineType}.omp.json"
    }

    # Nested symlinks
    FastFetch = @{
        Configuration = @{
            Path   = "{User}\.config\fastfetch\config.jsonc"
            Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
        }
        Logo = @{
            Path   = "{User}\.config\fastfetch\logo.txt"
            Target = "{RepoRoot}\FastFetch\Windows\logo_{MachineType}.txt"
        }
    }
}
```

### Pattern 3: Wallpapers Per Machine/Theme

```powershell
WallpaperDarkSettings = @{
    "PC" = @{
        Monitors = @(
            @{ File = "Space1.jpg"; Style = "Stretch" }
            @{ File = "Space2.jpg"; Style = "Stretch" }
        )
    }
    "Laptop" = @{ File = "BlackHole.png"; Style = "Fill" }
}
```

### Pattern 4: WSL Paths (Unix-style)

```powershell
SymbolicLinks = @{
    WSLSSH = @{
        Path   = "/home/you/.ssh/config"                    # WSL path
        Target = "{RepoRoot}/Server/.ssh/config"         # Forward slashes work
    }
    WSLFastFetch = @{
        Configuration = @{
            Path   = "/home/you/fastfetch/config.jsonc"
            Target = "{RepoRoot}/FastFetch/Windows/WSL/config_WSL_{MachineType}.jsonc"
        }
    }
}
```

## The Expand-ConfigPaths Function

This function performs the actual placeholder replacement. Its real signature is
`Expand-ConfigPaths -Configuration <full config hashtable> -MachineType <type> [-RepoRoot <path>]`;
it reads `PathTemplates` and `BasePaths` from the configuration and delegates the recursive
substitution to `Expand-Hashtable`, which replaces each token via string `.Replace()`:

```powershell
# Conceptually, for every string value in the configuration:
$value = $value.
    Replace('{Dev}',         $BasePaths[$MachineType].Dev).
    Replace('{User}',        $BasePaths[$MachineType].User).
    Replace('{MachineType}', $MachineType).
    Replace('{RepoRoot}',    $RepoRoot).
    Replace('{AppData}',     $env:APPDATA)
```

See [`Expand-ConfigPaths`](../modules/bootstrap.md#expand-configpaths) for the full reference.

## Why Use Placeholders?

### ❌ Without Placeholders (Bad)

```powershell
# You'd need separate configs for each machine
Projects_PC = @{
    Root = "E:\Development\GitHub\MyProject"
}
Projects_Laptop = @{
    Root = "C:\Users\John\Projects\GitHub\MyProject"
}
```

### ✅ With Placeholders (Good)

```powershell
# One config works everywhere
Projects = @{
    Root = "{Dev}\MyProject"
}
```

## Debugging Placeholders

Check what values your placeholders expand to:

```powershell
# View current machine type
$global:MachineType

# View base paths for your machine
$global:Configuration.BasePaths[$global:MachineType]

# View expanded paths
$global:MachineSpecificPaths.Projects.Self.Root

# Force re-expansion
Load-PathConfiguration -RepoRoot "C:\path\to\WinuX"
```

## Common Patterns

### Project Paths

```powershell
Projects = @{
    Self = @{
        Root       = "{RepoRoot}"
        Modules    = "{RepoRoot}\Windows\PowerShell\Modules"
        Wallpapers = "{RepoRoot}\Wallpapers"
    }
}
```

### Symbolic Links

```powershell
SymbolicLinks = @{
    Git = @{
        Path   = "{User}\.gitconfig"              # Where symlink is created
        Target = "{RepoRoot}\Git\.gitconfig"  # What it points to
    }
    FastFetch = @{
        Configuration = @{
            Path   = "{User}\.config\fastfetch\config.jsonc"
            Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
        }
    }
}
```

### Environment Variables

```powershell
AutoEnvironmentVariables = @{
    "Conda"  = "{User}\miniconda3"
    "Claude" = "{User}\.local\bin"
}
```

## WSL Path Conversion

Placeholders also work with WSL paths. Forward slashes trigger automatic conversion:

```powershell
SymbolicLinks = @{
    WSLSSH = @{
        Path   = "/home/you/.ssh/config"                    # WSL path (note forward slashes)
        Target = "{RepoRoot}/Server/.ssh/config"         # Auto-converted to WSL format
    }
}
```

The `Expand-Hashtable` function detects forward slashes and converts Windows paths to their WSL `/mnt/c/...` equivalents.

## Accessing Expanded Paths

After configuration loads, access expanded paths via:

```powershell
# Get specific path
$MachineSpecificPaths.Projects.Self.Root

# Get all project paths
$MachineSpecificPaths.Projects

# Get universal configuration (no placeholders, static values)
$Configuration.Universal.FirefoxExe
```

## Best Practices

1. **Always use `{Dev}` for project paths** - Handles different drive letters
2. **Use `{User}` for user-specific paths** - Handles different usernames
3. **Use `{MachineType}` for config files** - Machine-specific configs
4. **Use `{RepoRoot}` for WinuX-relative paths** - No hardcoding

## Next Steps

- Learn about [Machine Types](machine-types.md)
- See [Adding a New Machine](guides/add-new-machine.md) for practical examples

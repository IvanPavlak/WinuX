# Expand-ConfigPaths

Expands placeholder tokens (`{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}`) in configuration paths with their actual values based on machine type and base paths, then applies machine-specific overrides.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type) | hashtable of machine type to `@{ Dev; User }` | hashtable, 2 keys (`Machine`, `Test`) | The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong. |
| [`MachineOverrides`](../../configuration-reference.md#more-sections-quick-reference) | hashtable of machine type to value map | `@{ Machine = @{}; Test = @{} }` | Values merged over the expanded paths *after* placeholder expansion - the escape hatch for the handful of things that cannot be templated. Ships empty. |
| [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system) | hashtable, 11 keys | hashtable, 11 keys (several ship empty) | Every templated path in WinuX, expanded per machine by `Expand-ConfigPaths` into `$global:MachineSpecificPaths`. Includes `Projects` (per-project roots, including `Projects.Self` - the WinuX checkout itself), `SymbolicLinks`, `DockerDirectory`, `NuGetConfig`, `TaskbarLayoutFile`, and the personal paths that ship empty (`ObsidianDirectory`, `TrainingDirectory`, `LearningBook`, `Dnd`). |

## Decisions

1. What is the development root on this machine (the directory your repositories live in)?
    - Options: An absolute path, e.g. `C:\Users\You\Development\GitHub` or `D:\Dev`.
    - Default: The shipped `Machine` entry. Confirm it matches this machine before relying on it.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)
2. What is the user root on this machine?
    - Options: Normally your profile directory, e.g. `C:\Users\You`.
    - Default: The shipped `Machine` entry.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)
3. Which machine types need their own `BasePaths` entry?
    - Options: One entry per machine type you use. A type with no entry falls back to nothing and templated paths come out empty. [Add New Machine](../bootstrap/add-new-machine.md) lists everything a new type needs.
    - Default: Only the type this machine resolves to.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)
4. Is there a path on this machine that placeholders cannot express?
    - Options: A per-machine-type map of final values. Use this only when `PathTemplates` plus `BasePaths` genuinely cannot produce the path.
    - Default: Empty - nothing overridden.
    - More detail: [`MachineOverrides`](../../configuration-reference.md#more-sections-quick-reference)
5. Which templated paths does this machine need?
    - Options: Any of the 11 keys. Values use `{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}`. The personal ones ship empty and their consumers warn and return until set.
    - Default: The shipped templates - which means the personal paths stay off.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)
6. Do you need per-project roots under `PathTemplates.Projects`?
    - Options: One sub-hashtable per project, e.g. `MyProject = @{ Root = "{Dev}\MyProject" }`. `Projects.Self` is WinuX own checkout and is normally left alone.
    - Default: The shipped `Projects` map.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)
7. Do you need symbolic links under `PathTemplates.SymbolicLinks`?
    - Options: See [Add Symbolic Link](../system/add-symbolic-link.md) - the shape is `@{ <Group> = @{ <Name> = @{ Source; Target } } }`.
    - Default: The shipped map.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BasePaths`
2. Set `MachineOverrides`
3. Set `PathTemplates`
4. Reload and confirm the merge landed

## Step 1: Set `BasePaths`

The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong.

```powershell
BasePaths = @{
    Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

## Step 2: Set `MachineOverrides`

Values merged over the expanded paths *after* placeholder expansion - the escape hatch for the handful of things that cannot be templated. Ships empty.

```powershell
MachineOverrides = @{
    Machine = @{
        SomePath = "E:\Special\Location"
    }
}
```

## Step 3: Set `PathTemplates`

Every templated path in WinuX, expanded per machine by `Expand-ConfigPaths` into `$global:MachineSpecificPaths`. Includes `Projects` (per-project roots, including `Projects.Self` - the WinuX checkout itself), `SymbolicLinks`, `DockerDirectory`, `NuGetConfig`, `TaskbarLayoutFile`, and the personal paths that ship empty (`ObsidianDirectory`, `TrainingDirectory`, `LearningBook`, `Dnd`).

```powershell
PathTemplates = @{
    ObsidianDirectory = "{Dev}\Obsidian"
    Projects = @{
        MyProject = @{ Root = "{Dev}\MyProject" }
    }
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BasePaths
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BasePaths
$global:Configuration.MachineOverrides
$global:Configuration.PathTemplates
$global:MachineSpecificPaths | ConvertTo-Json -Depth 4
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BasePaths = @{
        Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
        Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    }
    MachineOverrides = @{
        Machine = @{
            SomePath = "E:\Special\Location"
        }
    }
    PathTemplates = @{
        ObsidianDirectory = "{Dev}\Obsidian"
        Projects = @{
            MyProject = @{ Root = "{Dev}\MyProject" }
        }
    }
}
```

## Related

- [`Expand-ConfigPaths` in the Bootstrap module reference](../../../modules/bootstrap.md#expand-configpaths) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Load-PathConfiguration`](Load-PathConfiguration.md) - reads the same configuration
- [`Set-EnvironmentVariables`](../system/Set-EnvironmentVariables.md) - reads the same configuration
- [`Set-SpecialFolders`](../system/Set-SpecialFolders.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

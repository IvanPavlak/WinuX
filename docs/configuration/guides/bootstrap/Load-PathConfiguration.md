# Load-PathConfiguration

Loads `Configuration.psd1`, detects the machine type, expands path placeholders, and registers the custom Modules directory for autoload.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type) | hashtable of machine type to `@{ Dev; User }` | hashtable, 2 keys (`Machine`, `Test`) | The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong. |
| [`DefaultMachineType`](../../configuration-reference.md#default-machine-type) | string | `"Test"` | The machine type used when the hostname is not in `HostnameToMachineType`. This is the safety net behind machine detection. |
| [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping) | hashtable of hostname to machine type | `@{ Test = "Test" }` | How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`. |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 26 keys | hashtable, 26 keys | Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too. |

This is where the merge you are relying on actually happens: the base `Configuration.psd1` is imported, `Configuration.local.psd1` is deep-merged over it by `Merge-Hashtable`, `Universal` is expanded in place, and `Expand-ConfigPaths` produces `$global:MachineSpecificPaths`. If a value you set is not showing up, inspect it here first - `$global:Configuration.<Key>` after a reload is the ground truth for whether your local file landed.

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
4. Which machine type should an unrecognised hostname fall back to?
    - Options: A member of `ValidMachineTypes`. Pick the most conservative type you have.
    - Default: `Test`.
    - More detail: [`DefaultMachineType`](../../configuration-reference.md#default-machine-type)
5. What is this machine hostname, and which machine type should it map to?
    - Options: Hostname to machine type. The machine type must be in `ValidMachineTypes`. [Add New Machine](../bootstrap/add-new-machine.md) walks the whole set of keys a new type needs.
    - Default: Unmapped, so the machine resolves to `DefaultMachineType`.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)
6. Do you have other machines to map now?
    - Options: One entry per hostname you own. Mapping several hostnames to the same type is normal.
    - Default: Just this machine.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)
7. Which browser should be the default?
    - Options: A key from `Universal.Browsers`: `Firefox`, `Chrome`, `Edge`, `Brave`, `Tor`. Ships empty, so `Open-Browser` asks or uses the system default.
    - Default: Empty.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
8. Are any of the shipped executable paths wrong on this machine?
    - Options: Override the individual `Universal.<App>Exe` value. Absolute paths, or placeholder paths such as `{User}\AppData\Local\...`.
    - Default: The shipped paths, which assume default install locations.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
9. Do you use a browser the base `Browsers` map does not list?
    - Options: Add an entry with `Exe`, `PrivateArg` and `NewWindowArg`. Because hashtables merge per key, adding one browser does not remove the others.
    - Default: The shipped five.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BasePaths`
2. Set `DefaultMachineType`
3. Set `HostnameToMachineType`
4. Set `Universal`
5. Reload and confirm the merge landed

## Step 1: Set `BasePaths`

The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong.

```powershell
BasePaths = @{
    Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

## Step 2: Set `DefaultMachineType`

The machine type used when the hostname is not in `HostnameToMachineType`. This is the safety net behind machine detection.

```powershell
DefaultMachineType = "Test"
```

## Step 3: Set `HostnameToMachineType`

How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`.

```powershell
HostnameToMachineType = @{
    Test             = "Test"
    "DESKTOP-GAMING" = "Machine"
}
```

## Step 4: Set `Universal`

Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too.

```powershell
Universal = @{
    DefaultBrowser = "Firefox"
    Browsers = @{
        Vivaldi = @{
            Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
            PrivateArg   = "--incognito"
            NewWindowArg = "--new-window"
        }
    }
}
```

## Step 5: Reload and confirm the merge landed

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
$global:Configuration.DefaultMachineType
$global:Configuration.HostnameToMachineType
$global:Configuration.Universal
$global:MachineType
$global:Configuration.Keys.Count
$global:MachineSpecificPaths.Projects.Self.Root
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
    DefaultMachineType = "Test"
    HostnameToMachineType = @{
        Test             = "Test"
        "DESKTOP-GAMING" = "Machine"
    }
    Universal = @{
        DefaultBrowser = "Firefox"
        Browsers = @{
            Vivaldi = @{
                Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
                PrivateArg   = "--incognito"
                NewWindowArg = "--new-window"
            }
        }
    }
}
```

## Related

- [`Load-PathConfiguration` in the Bootstrap module reference](../../../modules/bootstrap.md#load-pathconfiguration) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Expand-ConfigPaths`](Expand-ConfigPaths.md) - reads the same configuration
- [`Set-EnvironmentVariables`](../system/Set-EnvironmentVariables.md) - reads the same configuration
- [`Set-SpecialFolders`](../system/Set-SpecialFolders.md) - reads the same configuration
- [`Bootstrap`](Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

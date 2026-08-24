# Set-SpecialFolders

Redirects Windows special folders (such as Downloads and Screenshots) to custom paths defined in the `SpecialFolders` key of `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type) | hashtable of machine type to `@{ Dev; User }` | hashtable, 2 keys (`Machine`, `Test`) | The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong. |
| [`SpecialFolders`](../../configuration-reference.md#more-sections-quick-reference) | array of registry entries | `@()` (empty) | Special-folder redirections `Set-SpecialFolders` applies - for example pointing Downloads or Screenshots at the Desktop. Ships empty. |

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
4. Do you want any special folders redirected?
    - Options: One entry per folder (`Path`, `Name`, `Value`, `Description`). Values accept placeholders.
    - Default: Empty - `Set-SpecialFolders` no-ops.
    - More detail: [`SpecialFolders`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `SpecialFolders` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `BasePaths`
2. Set `SpecialFolders`
3. Reload and confirm the merge landed

## Step 1: Set `BasePaths`

The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong.

```powershell
BasePaths = @{
    Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

## Step 2: Set `SpecialFolders`

Special-folder redirections `Set-SpecialFolders` applies - for example pointing Downloads or Screenshots at the Desktop. Ships empty.

```powershell
SpecialFolders = @(
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"; Name = "{374DE290-123F-4565-9164-39C4925E467B}"; Value = "{User}\Desktop\Downloads"; Description = "Downloads to Desktop" }
)
```

## Step 3: Reload and confirm the merge landed

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
$global:Configuration.SpecialFolders
$global:Configuration.SpecialFolders | Format-Table Name, Value
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
    SpecialFolders = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"; Name = "{374DE290-123F-4565-9164-39C4925E467B}"; Value = "{User}\Desktop\Downloads"; Description = "Downloads to Desktop" }
    )
}
```

## Related

- [`Set-SpecialFolders` in the System module reference](../../../modules/system.md#set-specialfolders) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Expand-ConfigPaths`](../bootstrap/Expand-ConfigPaths.md) - reads the same configuration
- [`Load-PathConfiguration`](../bootstrap/Load-PathConfiguration.md) - reads the same configuration
- [`Set-EnvironmentVariables`](Set-EnvironmentVariables.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

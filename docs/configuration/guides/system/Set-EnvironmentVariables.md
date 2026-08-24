# Set-EnvironmentVariables

Sets user environment variables from the configuration or manually.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AutoEnvironmentVariables`](../../configuration-reference.md#more-sections-quick-reference) | hashtable of variable name to path | `@{}` (empty) | User environment variables `Set-EnvironmentVariables -Auto` writes. Values accept placeholders. |
| [`AutoPathAdditions`](../../configuration-reference.md#more-sections-quick-reference) | array of directory paths | `@()` (empty) | Directories `Set-EnvironmentVariables` persists onto the User `PATH`. |
| [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type) | hashtable of machine type to `@{ Dev; User }` | hashtable, 2 keys (`Machine`, `Test`) | The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong. |

## Decisions

1. Which user environment variables should WinuX keep set on this machine?
    - Options: Name to value pairs. Values may use `{Dev}`, `{User}`, `{RepoRoot}`, `{AppData}`.
    - Default: Empty - `Set-EnvironmentVariables -Auto` writes nothing.
    - More detail: [`AutoEnvironmentVariables`](../../configuration-reference.md#more-sections-quick-reference)
2. Which directories should be added to your User PATH?
    - Options: Absolute or placeholder paths, one per entry. Already-present entries are left alone.
    - Default: Empty - PATH is not modified.
    - More detail: [`AutoPathAdditions`](../../configuration-reference.md#more-sections-quick-reference)
3. What is the development root on this machine (the directory your repositories live in)?
    - Options: An absolute path, e.g. `C:\Users\You\Development\GitHub` or `D:\Dev`.
    - Default: The shipped `Machine` entry. Confirm it matches this machine before relying on it.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)
4. What is the user root on this machine?
    - Options: Normally your profile directory, e.g. `C:\Users\You`.
    - Default: The shipped `Machine` entry.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)
5. Which machine types need their own `BasePaths` entry?
    - Options: One entry per machine type you use. A type with no entry falls back to nothing and templated paths come out empty. [Add New Machine](../bootstrap/add-new-machine.md) lists everything a new type needs.
    - Default: Only the type this machine resolves to.
    - More detail: [`BasePaths`](../../configuration-reference.md#base-paths-per-machine-type)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `AutoPathAdditions` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `AutoEnvironmentVariables`
2. Set `AutoPathAdditions`
3. Set `BasePaths`
4. Reload and confirm the merge landed

## Step 1: Set `AutoEnvironmentVariables`

User environment variables `Set-EnvironmentVariables -Auto` writes. Values accept placeholders.

```powershell
AutoEnvironmentVariables = @{
    DEV_ROOT     = "{Dev}"
    WINUX_ROOT   = "{RepoRoot}"
}
```

## Step 2: Set `AutoPathAdditions`

Directories `Set-EnvironmentVariables` persists onto the User `PATH`.

```powershell
AutoPathAdditions = @(
    "{User}\AppData\Local\Programs\oh-my-posh\bin"
)
```

## Step 3: Set `BasePaths`

The two root directories every placeholder path is built from, per machine type. `{Dev}` expands to `Dev`, `{User}` to `User`. This is the single most load-bearing key: get it wrong and every templated path is wrong.

```powershell
BasePaths = @{
    Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.AutoEnvironmentVariables
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.AutoEnvironmentVariables
$global:Configuration.AutoPathAdditions
$global:Configuration.BasePaths
$global:Configuration.AutoEnvironmentVariables
[Environment]::GetEnvironmentVariable("DEV_ROOT", "User")
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AutoEnvironmentVariables = @{
        DEV_ROOT     = "{Dev}"
        WINUX_ROOT   = "{RepoRoot}"
    }
    AutoPathAdditions = @(
        "{User}\AppData\Local\Programs\oh-my-posh\bin"
    )
    BasePaths = @{
        Machine = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
        Test    = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    }
}
```

## Related

- [`Set-EnvironmentVariables` in the System module reference](../../../modules/system.md#set-environmentvariables) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Expand-ConfigPaths`](../bootstrap/Expand-ConfigPaths.md) - reads the same configuration
- [`Load-PathConfiguration`](../bootstrap/Load-PathConfiguration.md) - reads the same configuration
- [`Set-SpecialFolders`](Set-SpecialFolders.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

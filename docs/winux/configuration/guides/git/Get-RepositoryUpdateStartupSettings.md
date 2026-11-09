# Get-RepositoryUpdateStartupSettings

Deprecated: reads `RepositoryUpdate.Startup` with every default filled in - whether the automatic repository update is on, its schedule, the hour a day starts, and the interval.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0**, together with the `RepositoryUpdate.Startup` keys it reads. The automatic repository update is a startup task now, and [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md) replaces this function: it reads `Startup.Tasks`, and carries these keys over as a task named `RepositoryUpdate` for as long as they are set. This function keeps working unchanged until 3.0.0. Do not configure anything new here - write one `Startup.Tasks` entry instead, as the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide shows.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryUpdate.Startup.Enabled`](../../configuration-reference.md#repository-update) | bool | `$false` | Whether the automatic update runs at all. |
| [`RepositoryUpdate.Startup.Schedule`](../../configuration-reference.md#repository-update) | string | `"Daily"` | `"Daily"` or `"Interval"`; anything else is read as `"Daily"`. |
| [`RepositoryUpdate.Startup.DayStartHour`](../../configuration-reference.md#repository-update) | int | `6` | Daily only: the hour (0-23) a new day starts. Out of range or not a number reads as `6`. |
| [`RepositoryUpdate.Startup.IntervalHours`](../../configuration-reference.md#repository-update) | int | `24` | Interval only: minimum hours between two runs. Not a number reads as `24`. |

## Decisions

1. Should the repositories update on their own?
    - Options: `$true` or `$false` for the deprecated key - or, the way to answer this from 2.12.0 on, a `Startup.Tasks` entry named `RepositoryUpdate`, which replaces all the keys on this page. The migration is on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.
    - Default: `$false`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)
2. Once a day, or every so many hours?
    - Options: `"Daily"` (the first shell after the day starts, or the first prompt of a shell already open then) or `"Interval"` (at most once per `IntervalHours`, checked when a shell starts).
    - Default: `"Daily"`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)
3. When does your day start, or how long is the interval?
    - Options: `DayStartHour` from `0` to `23` for `"Daily"`; `IntervalHours` in hours for `"Interval"`.
    - Default: `6` and `24`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`RepositoryUpdate` and `Startup` are hashtables, so each key can be set on its own.

## Steps Overview

1. Set `RepositoryUpdate.Startup`
2. Reload and confirm the merge landed

## Step 1: Set `RepositoryUpdate.Startup`

The deprecated shape, still honoured until 3.0.0. The same update as a startup task is `Startup = @{ Tasks = @( @{ Name = "RepositoryUpdate"; Command = "Update-Repositories -All -NoClone -Quiet"; Trigger = "TerminalOpen"; Frequency = "OncePerDay" } ) }`.

```powershell
RepositoryUpdate = @{
    Startup = @{
        Enabled      = $true
        Schedule     = "Daily"
        DayStartHour = 6
    }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Get-RepositoryUpdateStartupSettings
```

## Verification

Read-only checks. None of these change anything.

```powershell
# The values the update acts on, defaults filled in
Get-RepositoryUpdateStartupSettings

# What you wrote, before defaults
$global:Configuration.RepositoryUpdate.Startup

# The startup task these keys are carried over as (Legacy = True), or the one you defined yourself
Get-StartupTaskDefinitions -Name RepositoryUpdate | Format-List Name, Trigger, Valid, Legacy
```

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    RepositoryUpdate = @{
        Startup = @{
            Enabled       = $true
            Schedule      = "Daily"
            DayStartHour  = 6
            IntervalHours = 24
        }
    }
}
```

## Related

- [`Get-RepositoryUpdateStartupSettings` in the Git module reference](../../../modules/git.md#get-repositoryupdatestartupsettings) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md) - the replacement
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the update these keys drove, and the migration to a startup task
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you

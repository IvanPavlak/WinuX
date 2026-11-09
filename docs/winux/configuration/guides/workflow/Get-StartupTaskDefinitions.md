# Get-StartupTaskDefinitions

Reads the startup tasks of the configuration, validated and with every default filled in - the one place that knows the shape of a `Startup.Tasks` entry.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

The walkthrough for defining a task, with every key explained, is on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide. This page covers what this function reads and how to check the result.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) | array of hashtables | `@()` (empty) | The startup tasks. Each entry is checked: an unknown key, a missing or repeated `Name`, an unknown `Trigger`, `Window`, `KeepOpen`, `Frequency` or `Elevation`, a number out of range, or a `Requires` name with no condition makes the task not valid, and a task that is not valid never runs. |
| [`Startup.Conditions`](../../configuration-reference.md#startup-tasks) | hashtable | one entry, `Network` | Only the names are read here, to check every task's `Requires`. |
| [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) | hashtable | `Enabled = $false` | **Deprecated since 2.12.0, removed in 3.0.0.** While `Enabled` is `$true` and no task is named `RepositoryUpdate`, one is added that does what these keys describe: the `TerminalOpen` trigger, `OncePerDay` (or `Interval` for `Schedule = "Interval"`), with `DayStartHour` and `IntervalHours` carried over. It is marked `Legacy` in the output. |
| [`RepositoryUpdate.Startup.Scope`](../../configuration-reference.md#repository-update) | hashtable | absent | Deprecated with the rest: which groups the carried-over task updates on this machine type. Absent falls back to [`BootstrapConfig.RepositoryUpdateScope`](../../configuration-reference.md#bootstrapconfig), then to every group. |

## Decisions

1. Which startup tasks should this machine have?
    - Options: One hashtable per task in `Startup.Tasks`. `Name` and `Trigger` are required; every other key has a default. The decisions for each key are on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide, which owns them; this function only reads and validates.
    - Default: None - `Startup.Tasks` ships empty.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
2. Are you still using the deprecated `RepositoryUpdate.Startup` keys?
    - Options: Keep them until 3.0.0 - they are turned into a task named `RepositoryUpdate` at every read, and `Test-ConfigurationSchema` warns about `RepositoryUpdate.Startup.Enabled` at every profile load. Or replace them with one `Startup.Tasks` entry and delete the block; a task of your own named `RepositoryUpdate` switches the carry-over off.
    - Default: The keys ship off, so nothing is carried over.
    - More detail: [`Invoke-StartupRepositoryUpdate`](../git/Invoke-StartupRepositoryUpdate.md)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`Startup.Tasks` is an array, so your local file holds the complete list of tasks.

## Steps Overview

1. Set `Startup.Tasks`
2. Reload and confirm the merge landed

## Step 1: Set `Startup.Tasks`

```powershell
Startup = @{
    Tasks = @(
        @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = "SignIn"; Machine = "PC/Laptop" }
    )
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the list back. `InScope` says whether the task applies to this machine (`Machine` and `Hostname`); `Valid` whether it can run at all.

```powershell
Reload-PowerShellProfile
Get-StartupTaskDefinitions | Format-Table Name, Trigger, InScope, Valid, Legacy
```

## Verification

Read-only checks. None of these change anything.

```powershell
# Every configured task and whether it applies to this machine
Get-StartupTaskDefinitions | Format-Table Name, Trigger, InScope, Valid, Legacy

# Why a task is not valid
Get-StartupTaskDefinitions | Where-Object { -not $_.Valid } | Format-List Name, Errors

# The tasks a sign-in runs here
Get-StartupTaskDefinitions -Trigger SignIn | Where-Object { $_.Valid -and $_.InScope }

# One task, with every default filled in: the parameters Invoke-StartupTask receives
(Get-StartupTaskDefinitions -Name MyTask).Parameters

# What you wrote, before validation
$global:Configuration.Startup.Tasks
```

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Startup = @{
        Tasks = @(
            @{ Name = "RepositoryUpdate"; Command = "Update-Repositories -All -NoClone -Quiet"; Trigger = "TerminalOpen"; Frequency = "OncePerDay" }
            @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = "SignIn"; Machine = "PC/Laptop" }
        )
    }
}
```

## Related

- [`Get-StartupTaskDefinitions` in the Workflow module reference](../../../modules/workflow.md#get-startuptaskdefinitions) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTasks`](Invoke-StartupTasks.md) - the walkthrough: every key of a task, from nothing to a working task
- [`Invoke-StartupTask`](Invoke-StartupTask.md) - receives the `Parameters` of each definition
- [`Set-StartupTasks`](../bootstrap/Set-StartupTasks.md) and [`Register-StartupTaskPromptCheck`](Register-StartupTaskPromptCheck.md) - the two other readers of the list
- [`Test-MachineTypeScope`](../bootstrap/Test-MachineTypeScope.md) - matches `Machine`
- [`Resolve-RepositoryUpdateScope`](../bootstrap/Resolve-RepositoryUpdateScope.md) - resolves the scope of the carried-over repository update
- [`Invoke-StartupRepositoryUpdate`](../git/Invoke-StartupRepositoryUpdate.md) - the migration from `RepositoryUpdate.Startup`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

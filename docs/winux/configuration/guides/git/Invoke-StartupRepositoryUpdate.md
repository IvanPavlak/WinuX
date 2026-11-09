# Invoke-StartupRepositoryUpdate

Deprecated wrapper that runs the startup task named `RepositoryUpdate` - the automatic repository update is a startup task now.

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0.** Use [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) `-Trigger TerminalOpen` (what the profile calls) or [`Invoke-StartupTask`](../workflow/Invoke-StartupTask.md) `RepositoryUpdate -Force` (run it now), and replace the `RepositoryUpdate.Startup` keys with one `Startup.Tasks` entry as shown under [Migration](#migration). The function keeps working until 3.0.0 and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It only forwards to the startup task `RepositoryUpdate`, which is configured as a [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) entry on the [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) guide. The deprecated [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) keys this page used to own are now read by [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md), which turns them into that task.

## Usage

```powershell
# Deprecated: runs the RepositoryUpdate startup task in this shell, if it is due
Invoke-StartupRepositoryUpdate
Invoke-StartupRepositoryUpdate -Force
Invoke-StartupRepositoryUpdate -Force -RedrawPrompt

# The replacements
Invoke-StartupTasks -Trigger TerminalOpen
Invoke-StartupTask RepositoryUpdate -Force
```

### Migration

Replace the `RepositoryUpdate.Startup` block in `Configuration.local.psd1` with one entry of `Startup.Tasks`, then delete the block.

Before:

```powershell
RepositoryUpdate = @{
    Startup = @{
        Enabled      = $true
        Schedule     = "Daily"
        DayStartHour = 6
    }
}
```

After:

```powershell
Startup = @{
    Tasks = @(
        @{
            Name      = "RepositoryUpdate"
            Command   = "Update-Repositories -All -NoClone -Quiet"
            Trigger   = "TerminalOpen"
            Frequency = "OncePerDay"
        }
    )
}
```

Key by key:

| Deprecated key | Replacement in the `Startup.Tasks` entry |
| -------------- | ---------------------------------------- |
| `Startup.Enabled = $true` | The entry itself. `Enabled = $false` on the entry parks it. |
| `Startup.Schedule = "Daily"` | `Frequency = "OncePerDay"` |
| `Startup.DayStartHour` | `DayStartHour` (default `6`) |
| `Startup.Schedule = "Interval"` | `Frequency = "Interval"` |
| `Startup.IntervalHours` | `IntervalHours` (default `24`) |
| `Startup.Scope` (per machine type) | One task per scope: `Machine` says where it runs, and the command names the groups with `-Group`. |

A per-machine `Scope` such as `@{ Default = "All"; Test = "Private" }` becomes two tasks. `Machine` has no `Default`, so the first one lists the machine types it covers:

```powershell
Startup = @{
    Tasks = @(
        @{ Name = "RepositoryUpdate"; Command = "Update-Repositories -All -NoClone -Quiet"; Trigger = "TerminalOpen"; Frequency = "OncePerDay"; Machine = "PC/Laptop/Work" }
        @{ Name = "RepositoryUpdate-Test"; Command = "Update-Repositories -Group Private -NoClone -Quiet"; Trigger = "TerminalOpen"; Frequency = "OncePerDay"; Machine = "Test" }
    )
}
```

What a startup task adds over the old keys: it can also run hidden at sign-in (`Trigger = @("SignIn", "TerminalOpen")`, `Window = "Hidden"`), and it can wait for the network (`Requires = @("Network")`). Keep one task named `RepositoryUpdate`: that name is what switches the legacy carry-over off, and what this wrapper runs.

### The legacy keys still work until 3.0.0

Nothing breaks if you do not migrate yet. While `RepositoryUpdate.Startup.Enabled` is `$true` and no startup task is named `RepositoryUpdate`, `Get-StartupTaskDefinitions` adds one that does what the keys describe: the `TerminalOpen` trigger, once per day or per interval, `Update-Repositories -All -NoClone -Quiet` or `-Group` with the groups `Startup.Scope` (then `BootstrapConfig.RepositoryUpdateScope`) names for this machine type. `Test-ConfigurationSchema` reports the key as deprecated at every profile load and at the start of every `Bootstrap`; it is a warning, never an error.

Three things differ from before 2.12.0, with or without the migration:

- The stamp and the lock are the startup task's: `Logs\.startup-task-RepositoryUpdate.stamp` and `Logs\.startup-task-RepositoryUpdate.lock`. `Logs\.last-repository-update` is no longer written, so the first shell after the upgrade runs the update once more.
- The stamp is written only after a run that succeeded. A run that threw is tried again in the next shell, not on the next day.
- The profile stage is named `StartupTasks`, not `RepositoryUpdate`: to start one shell without it, `$env:WINUX_STARTUP_SKIP = "StartupTasks"`.

Read-only checks for either shape:

```powershell
# The task, whether it comes from Startup.Tasks or from the legacy keys (Legacy = True)
Get-StartupTaskDefinitions -Name RepositoryUpdate | Format-List Name, Trigger, InScope, Valid, Legacy
(Get-StartupTaskDefinitions -Name RepositoryUpdate).Parameters

# Would a new terminal run it now?
Invoke-StartupTasks -Trigger TerminalOpen -Name RepositoryUpdate -WhatIf
```

## Related

- [`Invoke-StartupRepositoryUpdate` in the Git module reference](../../../modules/git.md#invoke-startuprepositoryupdate) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) - the replacement, and the startup tasks walkthrough
- [`Invoke-StartupTask`](../workflow/Invoke-StartupTask.md) - runs the `RepositoryUpdate` task by name
- [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md) - reads the legacy keys and builds the carried-over task
- [`Update-Repositories`](Update-Repositories.md) - what the task runs, and the default-branch setting
- [`Resolve-RepositoryUpdateScope`](../bootstrap/Resolve-RepositoryUpdateScope.md) - resolves the legacy `Startup.Scope`
- [`Measure-ShellStartup`](../system/Measure-ShellStartup.md) - the startup stages, `StartupTasks` among them
- [Configuration reference](../../configuration-reference.md) - every key, section by section

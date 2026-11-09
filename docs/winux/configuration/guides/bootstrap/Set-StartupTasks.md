# Set-StartupTasks

Registers the Windows scheduled tasks that run the configured startup tasks at sign-in, unlock and wake, and removes the ones nothing needs any more.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

Startup tasks are run by [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md); this function is what makes Windows call it. The walkthrough for defining a task is on that guide. This page covers the registration.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) | array of hashtables | `@()` (empty) | Read through [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md). Only valid, enabled tasks in this machine's scope count. Each of the triggers `SignIn`, `Unlock` and `Wake` that at least one of them uses gets one scheduled task; `TerminalOpen` needs none. |
| [`Startup.Tasks[].Elevation`](../../configuration-reference.md#startup-tasks) | string | absent (unelevated) | A task with `"Silent"` gets a scheduled task of its own per trigger, run with the highest privileges, with its command, its options and its conditions copied in. |
| [`Startup.Conditions`](../../configuration-reference.md#startup-tasks) | hashtable | one entry, `Network` | The conditions a `Silent` task requires are copied into its scheduled task, so a later edit of a condition cannot change what runs elevated either. |
| [`BootstrapConfig.Steps.StartupTasks`](../../configuration-reference.md#bootstrapconfig) | bool or per-machine-type hashtable | `$true` (built-in default) | Whether `Bootstrap` calls this function, right after the symbolic links. Read by [`Resolve-BootstrapSteps`](Resolve-BootstrapSteps.md). |

What gets registered, under the Task Scheduler folder `\WinuX\`:

| Scheduled task | When it fires | What it runs |
| -------------- | ------------- | ------------ |
| `StartupTasks-SignIn` | This user signs in. | `Invoke-StartupTasks -Trigger SignIn`, unelevated |
| `StartupTasks-Unlock` | This user unlocks the workstation. | `Invoke-StartupTasks -Trigger Unlock`, unelevated |
| `StartupTasks-Wake` | The machine resumes from sleep (the System log's Power-Troubleshooter event 1). | `Invoke-StartupTasks -Trigger Wake`, unelevated |
| `StartupTask-Silent-<Name>-<Trigger>` | The same three events, for one `Silent` task. | That task alone, with the highest privileges |

Each runs in a shell with no window, as the signed-in user, on battery too.

## Decisions

1. Should Bootstrap keep the scheduled tasks in step with your configuration?
    - Options: `BootstrapConfig.Steps.StartupTasks`, a boolean or a per-machine-type hashtable with a `Default` fallback, like every other step. On, every Bootstrap registers what the configured tasks need and removes what is left over. Off, you run `Set-StartupTasks` yourself. `Bootstrap -Skip StartupTasks` and `-Include StartupTasks` override it per run.
    - Default: On. With `Startup.Tasks` empty the step finds nothing to do and registers nothing.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
2. Which triggers do your tasks use on this machine?
    - Options: Nothing to set here - it follows from the `Trigger`, `Machine`, `Hostname` and `Enabled` keys of your tasks. One scheduled task per trigger in use, not one per startup task: the list is read when the trigger fires, so editing a task needs no second run. Starting or stopping to use a whole trigger does.
    - Default: No triggers in use, no scheduled tasks.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
3. Does a task need to run as Administrator without a consent dialog?
    - Options: `Elevation = "Silent"` on the task. Its command is copied into an elevated scheduled task when this function runs, and is frozen there: a later edit of the configuration changes nothing for it until `Set-StartupTasks` runs again, which keeps a configuration edit from becoming Administrator rights without consent. **It is still a standing way to run that command as Administrator** - the command loads this repository's modules when it runs, so whatever it calls runs elevated. Use it only for a command you would run elevated without looking; `"Prompt"` (one consent dialog per run) is the careful choice.
    - Default: No `Silent` tasks, no elevated scheduled tasks.
    - More detail: [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`BootstrapConfig.Steps` is a hashtable, so writing only `StartupTasks` leaves every other step as shipped. `Startup.Tasks` is an array, so your local file holds the complete list.

## Steps Overview

1. Set `Startup.Tasks`
2. Reload and confirm the merge landed
3. Run `Set-StartupTasks`

## Step 1: Set `Startup.Tasks`

At least one task with the `SignIn`, `Unlock` or `Wake` trigger. The keys are explained on the [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) guide.

```powershell
Startup = @{
    Tasks = @(
        @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = "SignIn" }
    )
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then look at what this function would register. `Missing` is a scheduled task the configuration needs and Windows does not have yet.

```powershell
Reload-PowerShellProfile
Set-StartupTasks -List | Format-Table TaskName, Trigger, RunLevel, State
```

## Step 3: Run `Set-StartupTasks`

Registering and removing need Administrator privileges; from a non-elevated shell the function asks to rerun in the Administrator PowerShell, as every such function does. Running it again changes nothing but the registration time.

```powershell
Set-StartupTasks
```

The scheduled tasks are registered for the account the elevated shell runs as, so elevate as yourself. On a standard account that elevates with another administrator's credentials, they would fire at that administrator's sign-in, not yours. `Set-StartupTasks -Remove` removes every startup scheduled task, whatever the configuration says.

## Verification

Read-only checks. None of these change anything.

```powershell
# What this machine needs and what Windows has: Registered, Missing or Stale
Set-StartupTasks -List | Format-Table TaskName, Trigger, RunLevel, State

# What a run would register and remove, without doing it
Set-StartupTasks -WhatIf

# The tasks the registration is derived from
Get-StartupTaskDefinitions | Where-Object { $_.Valid -and $_.InScope } | Format-Table Name, Trigger

# Whether Bootstrap runs the step
Resolve-BootstrapSteps | Format-Table

# Windows' own view (nothing is printed while the folder does not exist)
Get-ScheduledTask -TaskPath '\WinuX\' -ErrorAction SilentlyContinue | Format-Table TaskName, State
```

`Registered` means a scheduled task of that name exists. For a `Silent` task it does not say the frozen copy is current: run `Set-StartupTasks` after every edit of such a task.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        Steps = @{
            StartupTasks = @{ Default = $true; Test = $false }
        }
    }
    Startup         = @{
        Tasks = @(
            @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = @("SignIn", "Unlock") }
            @{ Name = "MyMaintenance"; Command = "Clear-MyCache"; Trigger = "SignIn"; Window = "Hidden"; Elevation = "Silent"; Requires = @("Network") }
        )
    }
}
```

## Related

- [`Set-StartupTasks` in the Bootstrap module reference](../../../modules/bootstrap.md#set-startuptasks) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) - the walkthrough: defining a task, rehearsing it, and what each trigger does
- [`Get-StartupTaskDefinitions`](../workflow/Get-StartupTaskDefinitions.md) - the validated list this function registers from
- [`New-StartupTaskShellCommand`](../workflow/New-StartupTaskShellCommand.md) - builds the command each scheduled task runs
- [`Resolve-BootstrapSteps`](Resolve-BootstrapSteps.md) and [`Bootstrap`](Bootstrap.md) - the step `StartupTasks`
- [`Test-AdminPrivileges`](../helper/Test-AdminPrivileges.md) - the elevation this function asks for
- [Startup tasks troubleshooting](../../../reference/troubleshooting.md#startup-tasks) - a task that never runs at sign-in, a missing elevated task, the Wake trigger
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

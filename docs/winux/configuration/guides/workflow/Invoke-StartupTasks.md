# Invoke-StartupTasks

Runs the configured startup tasks of one trigger - sign-in, unlock, wake or a newly opened terminal - and is the page that walks you from nothing to a working startup task.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

A startup task is a command this machine runs on its own. You write it once as an entry of `Startup.Tasks`; Windows (through the scheduled tasks [`Set-StartupTasks`](../bootstrap/Set-StartupTasks.md) registers) or the profile then calls `Invoke-StartupTasks -Trigger <Trigger>`, which reads the list at that moment and hands every matching task to [`Invoke-StartupTask`](Invoke-StartupTask.md). The base ships no task, so nothing runs until you add one.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) | array of hashtables | `@()` (empty) | The startup tasks, run in the order they are written. Each entry is exactly a set of parameters for `Invoke-StartupTask`. Read through [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md), which validates every entry. |
| [`Startup.Tasks[].Name`](../../configuration-reference.md#startup-tasks) | string | required | Unique name: letters, digits, `-` and `_`. Names the task's stamp, lock and result files in the Logs directory. |
| [`Startup.Tasks[].Command`](../../configuration-reference.md#startup-tasks) | string | none | The command line to run, as typed at a prompt (aliases and functions work). Without one the task only opens a terminal. |
| [`Startup.Tasks[].Trigger`](../../configuration-reference.md#startup-tasks) | string or array | required | One or several of `"SignIn"`, `"Unlock"`, `"Wake"`, `"TerminalOpen"`. |
| [`Startup.Tasks[].Machine`](../../configuration-reference.md#startup-tasks) | string | absent (every machine) | Machine scope such as `"PC/Laptop"`, matched like everywhere else by `Test-MachineTypeScope`. |
| [`Startup.Tasks[].Hostname`](../../configuration-reference.md#startup-tasks) | string or array | absent (every machine) | One or several computer names. With `Machine`, both must match. |
| [`Startup.Tasks[].Requires`](../../configuration-reference.md#startup-tasks) | array of strings | `@()` | Names of `Startup.Conditions` entries the task waits for. |
| [`Startup.Tasks[].Window`](../../configuration-reference.md#startup-tasks) | string | `"Tab"` | `"Tab"` or `"Hidden"`: where a SignIn, Unlock or Wake run happens. A TerminalOpen run is always inline. |
| [`Startup.Tasks[].KeepOpen`](../../configuration-reference.md#startup-tasks) | string | `"OnFailure"` (`"Always"` without a `Command`) | `"OnFailure"`, `"Always"` or `"Never"`: whether the task's tab stays open when it is over. |
| [`Startup.Tasks[].Parallel`](../../configuration-reference.md#startup-tasks) | bool | `$false` | `$true` starts the task and goes on to the next without waiting for it. |
| [`Startup.Tasks[].Frequency`](../../configuration-reference.md#startup-tasks) | string | `"EveryTime"` | `"EveryTime"`, `"OncePerBoot"`, `"OncePerDay"` or `"Interval"`. Only a run that succeeded counts. |
| [`Startup.Tasks[].DayStartHour`](../../configuration-reference.md#startup-tasks) | int | `6` | `OncePerDay` only: the hour (0-23) a new day starts. |
| [`Startup.Tasks[].IntervalHours`](../../configuration-reference.md#startup-tasks) | number | `24` | `Interval` only: minimum hours between two successful runs. |
| [`Startup.Tasks[].Elevation`](../../configuration-reference.md#startup-tasks) | string | absent (unelevated) | `"Relaunch"`, `"Prompt"` or `"Silent"`: how a command that needs Administrator privileges gets them. `"None"` spells out the default. |
| [`Startup.Tasks[].Timeout`](../../configuration-reference.md#startup-tasks) | number | `600` | Seconds the runner waits for the task before it moves on. `0` waits without limit. The task itself is never stopped. |
| [`Startup.Tasks[].Enabled`](../../configuration-reference.md#startup-tasks) | bool | `$true` | `$false` parks the task without deleting it. |
| [`Startup.Conditions`](../../configuration-reference.md#startup-tasks) | hashtable | one entry, `Network` | Named tests a task can require: `<Name> = @{ Test; Timeout; Interval }`. Evaluated by [`Test-StartupCondition`](Test-StartupCondition.md). |
| [`Startup.FailureReport`](../../configuration-reference.md#startup-tasks) | string | `"Tab"` | `"Tab"`: after a SignIn, Unlock or Wake run in which a task failed, was skipped or timed out, one terminal tab lists them. `"None"`: only the log. |

The deprecated [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) keys still count: while `RepositoryUpdate.Startup.Enabled` is `$true` and no task is named `RepositoryUpdate`, one is added that does what those keys describe. See [`Invoke-StartupRepositoryUpdate`](../git/Invoke-StartupRepositoryUpdate.md) for the migration.

## Decisions

1. What should this machine run on its own, and what do you call it?
    - Options: `Command` is any command line you would type at a prompt: a WinuX function (`Open-Workspace MyWorkspace`), an alias, a program. `Name` is yours to choose (letters, digits, `-`, `_`) and must be unique. A task with no `Command` just opens a terminal. A command has failed only when it throws; an error it merely writes, or a non-zero exit code, does not count.
    - Default: No tasks. `Startup.Tasks` ships empty, so nothing runs.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
2. When should it run - at sign-in, at unlock, after waking from sleep, or whenever a terminal opens?
    - Options: `Trigger` is one or several of `"SignIn"` (when you sign in), `"Unlock"` (when you unlock the workstation), `"Wake"` (when the machine resumes from sleep) and `"TerminalOpen"` (once the first prompt of a new shell is drawn). Write several as an array: `@("SignIn", "TerminalOpen")`. `"Boot"` is rejected: nothing can run before sign-in, because a task needs your desktop and your saved credentials. The first three need the scheduled tasks `Set-StartupTasks` registers; `TerminalOpen` needs nothing but the profile.
    - Default: None - `Trigger` is required, and a task without one is reported as not valid and never runs.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
3. Where should it run - in a terminal tab you can watch, or hidden?
    - Options: `Window = "Tab"` opens a tab in a Windows Terminal window named `WinuXStartup`, shared by all tasks of that startup; `KeepOpen` then says whether the tab stays: `"OnFailure"` closes it unless the task failed, was skipped or was handed off to an Administrator tab, `"Always"` leaves it, `"Never"` closes it whatever happened. `Window = "Hidden"` runs the task in a shell with no window that cannot ask a question. A TerminalOpen run ignores both: it is always inline, in the shell that just opened, and prints under the prompt.
    - Default: `"Tab"` with `KeepOpen = "OnFailure"`; a task without a `Command` keeps its tab (`"Always"`).
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
4. What must be up before it runs?
    - Options: List condition names in `Requires`, and define each under `Startup.Conditions` as `@{ Test = '<command>'; Timeout = 60; Interval = 2 }`. The condition is met when the test's output is truthy, like the condition of an `if`; for a program whose exit code is the answer, end the test with `$LASTEXITCODE -eq 0`. The task waits up to `Timeout` seconds and is skipped when the condition never comes up. A TerminalOpen run tests each condition once and never waits, so a shell opened offline is not held up.
    - Default: No conditions. `Network` ships ready to use (an Internet-connected network profile, 60 seconds).
    - More detail: [`Test-StartupCondition`](Test-StartupCondition.md)
5. How often should it run?
    - Options: `Frequency = "EveryTime"` runs at every trigger; `"OncePerBoot"` once per restart (with Windows Fast Startup a shutdown is a hibernation, so only a restart counts); `"OncePerDay"` once per day, the day starting at `DayStartHour`, so work past midnight never counts as a new day; `"Interval"` at most once per `IntervalHours`. The stamp is written only after a run that succeeded, so a task that failed or was skipped is due again at the next trigger. A TerminalOpen task with `"OncePerDay"` also runs in a shell that stayed open overnight, at its first prompt after the day starts.
    - Default: `"EveryTime"`, with `DayStartHour = 6` and `IntervalHours = 24` for the two schedules.
    - More detail: [`Test-StartupTaskDue`](Test-StartupTaskDue.md)
6. Which machines should run it?
    - Options: Leave both keys out for every machine. `Machine = "PC/Laptop"` limits the task to those machine types, the same scope syntax as a taskbar row or a workspace action. `Hostname = "LAPTOP-PERSONAL"` (or an array) limits it to named computers, for a difference between two machines of the same type. With both, both must match.
    - Default: Every machine.
    - More detail: [Machine Types](../../machine-types.md#startup-tasks)
7. Does the command need Administrator privileges?
    - Options: Leave `Elevation` out (or write `"None"`) for an unelevated task; a command that then asks for Administrator fails at once with a message naming this key, instead of showing a question nobody is there to answer. `"Relaunch"` lets such a command rerun itself in an Administrator tab (Windows asks for consent). `"Prompt"` starts the whole task elevated, with one Windows consent dialog. `"Silent"` shows no dialog at all: `Set-StartupTasks` copies the command, its options and the conditions it requires into a scheduled task of its own that runs with the highest privileges. **`Silent` is a standing way to run that command as Administrator** - anything that can change what the command does (the function it calls, the repository's modules) changes what runs elevated without consent, so use it only for a command you would run elevated without looking. `"Prompt"` and `"Silent"` cannot be combined with the `TerminalOpen` trigger.
    - Default: Unelevated.
    - More detail: [`Set-StartupTasks`](../bootstrap/Set-StartupTasks.md)
8. Should the next task wait for this one?
    - Options: Tasks of one trigger run one after another, in the order written; the runner waits for each up to its `Timeout` seconds (`0` waits without limit) and then moves on without stopping it. `Parallel = $true` starts the task and goes straight on to the next; it is collected at the end. One task failing never stops the next.
    - Default: Sequential, `Timeout = 600`.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
9. How do you want to hear about a task that did not finish?
    - Options: `Startup.FailureReport = "Tab"` opens one terminal tab listing every task of a SignIn, Unlock or Wake run that failed, was skipped for a condition or timed out. `"None"` leaves it to the log. Every result is in the runner's session log either way, and a TerminalOpen run prints its problems in the shell it runs in.
    - Default: `"Tab"`.
    - More detail: [`Startup.FailureReport`](../../configuration-reference.md#startup-tasks)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`Startup` and `Startup.Conditions` are hashtables, so a condition of yours is added beside the shipped `Network`. `Startup.Tasks` is an array: the base ships it empty, so nothing is lost, but your local file always holds the complete list.

## Steps Overview

1. Define a condition in `Startup.Conditions`
2. Define a task in `Startup.Tasks`
3. Reload and confirm the merge landed
4. Rehearse the trigger with `-WhatIf`
5. Register the scheduled tasks with `Set-StartupTasks`
6. Check the registration and the log

## Step 1: Define a condition in `Startup.Conditions`

Skip this step when the task needs nothing, or only the shipped `Network`. Otherwise name what must be up and give the command that tells: the test below is met when the program `myvpn` exits with `0`.

```powershell
Startup = @{
    Conditions = @{
        MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
    }
}
```

## Step 2: Define a task in `Startup.Tasks`

One hashtable per task. This one opens a workspace at sign-in, on one named computer, once the VPN is up:

```powershell
Startup = @{
    Conditions = @{
        MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
    }
    Tasks      = @(
        @{
            Name     = "MyWorkspace"
            Command  = "Open-Workspace MyWorkspace"
            Trigger  = "SignIn"
            Hostname = "LAPTOP-PERSONAL"
            Requires = @("MyVpn")
        }
    )
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the tasks back as the runner sees them: validated, with every default filled in. A task with `Valid = False` never runs; its `Errors` say why (an unknown key, a missing `Trigger`, a `Requires` name with no condition).

```powershell
Reload-PowerShellProfile
Get-StartupTaskDefinitions | Format-Table Name, Trigger, InScope, Valid
(Get-StartupTaskDefinitions | Where-Object { -not $_.Valid }).Errors
```

## Step 4: Rehearse the trigger with `-WhatIf`

`-WhatIf` runs nothing and returns, per task, what the trigger would do right now on this machine: `WouldRun` (with the conditions it would still wait for), `NotDue`, `OutOfScope` or `Disabled`. It is the way to try a sign-in without signing out.

```powershell
Invoke-StartupTasks -Trigger SignIn -WhatIf | Format-Table Name, Status, Reason
```

To run one task for real, here and now, whatever its frequency says: `Invoke-StartupTask MyWorkspace -Force`.

## Step 5: Register the scheduled tasks with `Set-StartupTasks`

A task with the `SignIn`, `Unlock` or `Wake` trigger runs only once Windows knows to call the runner. `Set-StartupTasks` registers one scheduled task per trigger in use, under the Task Scheduler folder `\WinuX\`. It needs Administrator privileges and asks for them the usual way; Bootstrap runs it too, as the step `StartupTasks`.

```powershell
Set-StartupTasks
```

Run it from your own account, elevated: the scheduled tasks are registered for the account the elevated shell runs as. After that, editing `Startup.Tasks` needs no second run - the list is read when the trigger fires. Run it again only when you start or stop using a whole trigger, and after every change to a task with `Elevation = "Silent"`, whose command is frozen into its own scheduled task. A task that only has the `TerminalOpen` trigger needs no registration at all.

## Step 6: Check the registration and the log

`Set-StartupTasks -List` shows each scheduled task this machine needs and whether it is `Registered`, `Missing` or `Stale` (left over, removed by the next `Set-StartupTasks`). After the next sign-in, the runner's lines are in its own session log - the runner has no window, so that log is where its results land.

```powershell
Set-StartupTasks -List | Format-Table TaskName, Trigger, RunLevel, State
Get-ChildItem (Get-LogPath -Directory) -Filter "Session_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Select-String "Startup task"
```

## Verification

Read-only checks. None of these change anything or run a task.

```powershell
# The tasks as the runner reads them, and what is wrong with the ones that never run
Get-StartupTaskDefinitions | Format-Table Name, Trigger, InScope, Valid
(Get-StartupTaskDefinitions | Where-Object { -not $_.Valid }).Errors

# What each trigger would do on this machine right now
Invoke-StartupTasks -Trigger SignIn -WhatIf | Format-Table Name, Status, Reason
Invoke-StartupTasks -Trigger TerminalOpen -WhatIf | Format-Table Name, Status, Reason

# Which scheduled tasks exist, which are missing and which are left over
Set-StartupTasks -List | Format-Table TaskName, Trigger, RunLevel, State

# This shell's session log, the Logs directory, and what the last runs logged
Get-LogPath
Get-ChildItem (Get-LogPath -Directory) -Filter "Session_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Select-String "Startup task"

# The state files: one stamp per task that succeeded, and the last failure report per trigger
Get-ChildItem (Get-LogPath -Directory) -Filter ".startup-*"
```

If a task is missing from the list, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and `Tasks` placed outside the `Startup` hashtable. See [Startup tasks](../../../reference/troubleshooting.md#startup-tasks) in the troubleshooting page for a task that is listed and still does not run.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Startup = @{
        Conditions    = @{
            MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
        }
        Tasks         = @(
            # Update the repositories once a day: hidden at sign-in, or in the first terminal of the day
            @{
                Name      = "RepositoryUpdate"
                Command   = "Update-Repositories -All -NoClone -Quiet"
                Trigger   = @("SignIn", "TerminalOpen")
                Frequency = "OncePerDay"
                Requires  = @("Network")
                Window    = "Hidden"
                Parallel  = $true
            }
            # Open a workspace at sign-in on one computer, once the VPN is up
            @{
                Name     = "MyWorkspace"
                Command  = "Open-Workspace MyWorkspace"
                Trigger  = "SignIn"
                Hostname = "LAPTOP-PERSONAL"
                Requires = @("MyVpn")
            }
            # A hidden task every four hours, on two machine types, after sign-in, unlock or wake
            @{
                Name          = "MyTask"
                Command       = "Clear-MyCache"
                Trigger       = @("SignIn", "Unlock", "Wake")
                Machine       = "PC/Laptop"
                Window        = "Hidden"
                Frequency     = "Interval"
                IntervalHours = 4
                Timeout       = 120
            }
        )
        FailureReport = "Tab"
    }
}
```

## Related

- [`Invoke-StartupTasks` in the Workflow module reference](../../../modules/workflow.md#invoke-startuptasks) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTask`](Invoke-StartupTask.md) - runs one task; every key of an entry is one of its parameters
- [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md) - reads and validates `Startup.Tasks`
- [`Test-StartupCondition`](Test-StartupCondition.md) - evaluates `Startup.Conditions`
- [`Test-StartupTaskDue`](Test-StartupTaskDue.md) - the frequency check
- [`Register-StartupTaskPromptCheck`](Register-StartupTaskPromptCheck.md) - makes a shell left open overnight run its once-a-day tasks
- [`Set-StartupTasks`](../bootstrap/Set-StartupTasks.md) - registers the scheduled tasks behind SignIn, Unlock and Wake
- [`Test-AdminPrivileges`](../helper/Test-AdminPrivileges.md) - what a command that asks for Administrator does inside a startup task
- [`Invoke-StartupRepositoryUpdate`](../git/Invoke-StartupRepositoryUpdate.md) - the deprecated automatic repository update and its migration to a startup task
- [Startup tasks troubleshooting](../../../reference/troubleshooting.md#startup-tasks) - a task that never runs, runs again, or asks for Administrator
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

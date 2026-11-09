# Invoke-StartupTask

Runs one startup task - any command, with conditions, a frequency, a window and an elevation - either the configured task of a given name or one described entirely on the command line.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

Every key of a `Startup.Tasks` entry is a parameter of this function, so an entry is exactly a parameter set for it. The walkthrough for defining a task, with every key explained, is on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide; this page covers what the function itself reads.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) | array of hashtables | `@()` (empty) | Read (through [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md)) only when the function is called with a `-Name` and no `-Command`: the configured task of that name supplies every option the command line left out, except `Window`, `KeepOpen` and `Parallel` - a task typed at a prompt runs in that shell. |
| [`Startup.Conditions`](../../configuration-reference.md#startup-tasks) | hashtable | one entry, `Network` | Where the names in `-Requires` are looked up, unless `-ConditionDefinitions` is passed. |

## Decisions

1. Do you want to run a configured task, or try a command before you configure it?
    - Options: `Invoke-StartupTask MyTask` runs the `Startup.Tasks` entry named `MyTask` in the current shell; parameters given on the command line win over the entry's, and `-Force` passes the `Enabled` and frequency gates (never the machine scope). `Invoke-StartupTask -Name MyTask -Command "..."` needs no entry at all, which is how to try a command, a condition or a window before writing it down. `-WhatIf` says whether it would run now and runs nothing.
    - Default: Nothing is configured; a name with no entry and no `-Command` is reported as a failure.
    - More detail: [`Startup.Tasks`](../../configuration-reference.md#startup-tasks)
2. Which conditions can a task of yours wait for?
    - Options: Every name under `Startup.Conditions`. Add your own beside the shipped `Network`; a `-Requires` name with no entry counts as not met, so a typo never lets a task run early.
    - Default: `Network` only.
    - More detail: [`Test-StartupCondition`](Test-StartupCondition.md)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`Startup.Conditions` is a hashtable, so your condition is added beside `Network`. `Startup.Tasks` is an array, so your local file holds the complete list.

## Steps Overview

1. Set `Startup.Tasks` and `Startup.Conditions`
2. Reload and confirm the merge landed

## Step 1: Set `Startup.Tasks` and `Startup.Conditions`

A task to run by name, and the condition it requires. The full set of keys is on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide.

```powershell
Startup = @{
    Conditions = @{
        MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120 }
    }
    Tasks      = @(
        @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = "SignIn"; Requires = @("MyVpn") }
    )
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the task back as this function receives it.

```powershell
Reload-PowerShellProfile
(Get-StartupTaskDefinitions -Name MyTask).Parameters
```

## Verification

Read-only checks. None of these change anything or run a task.

```powershell
# The options the configured task would be run with
(Get-StartupTaskDefinitions -Name MyTask).Parameters

# Whether it would run now: WouldRun (and what it would wait for), NotDue, OutOfScope or Disabled
Invoke-StartupTask MyTask -WhatIf

# The same question for a command that is not configured anywhere
Invoke-StartupTask -Name MyTask -Command "Open-Workspace MyWorkspace" -Requires MyVpn -WhatIf
```

The result object's `Status` is one of `Succeeded`, `Failed`, `Skipped`, `TimedOut`, `Ended`, `Started`, `HandedOff`, `NotDue`, `OutOfScope`, `Disabled`, `AlreadyRunning` or, with `-WhatIf`, `WouldRun`; `Reason` says why.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Startup = @{
        Conditions = @{
            MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
        }
        Tasks      = @(
            @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Trigger = "SignIn"; Requires = @("MyVpn") }
        )
    }
}
```

## Related

- [`Invoke-StartupTask` in the Workflow module reference](../../../modules/workflow.md#invoke-startuptask) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTasks`](Invoke-StartupTasks.md) - the walkthrough: every key of a task, from nothing to a working task
- [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md) - supplies the configured task
- [`Test-StartupCondition`](Test-StartupCondition.md) - waits for each `-Requires` condition
- [`Test-StartupTaskDue`](Test-StartupTaskDue.md) - the frequency gate
- [`Start-StartupTaskShell`](Start-StartupTaskShell.md) and [`Wait-StartupTaskResult`](Wait-StartupTaskResult.md) - the tab or hidden shell of a task, and how its result comes back
- [`Test-AdminPrivileges`](../helper/Test-AdminPrivileges.md) - what `-Elevation` changes for a command that asks for Administrator
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

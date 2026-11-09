# Test-StartupCondition

Waits until a named startup condition is met - the network, a VPN, a service - or its timeout passes, and returns whether it was met.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

A startup task lists the conditions it needs in `Requires`. How a task uses them is on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide; this page is about defining one.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Startup.Conditions`](../../configuration-reference.md#startup-tasks) | hashtable | one entry, `Network` | The named conditions: `<Name> = @{ Test; Timeout; Interval }`. Looked up here unless `-Definitions` is passed. |
| [`Startup.Conditions.<Name>.Test`](../../configuration-reference.md#startup-tasks) | string | required | A command line. The condition is met when its output is truthy, like the condition of an `if`. A test that throws, prints nothing or does not parse has not met it. |
| [`Startup.Conditions.<Name>.Timeout`](../../configuration-reference.md#startup-tasks) | number | `60` | Seconds to keep testing before giving up. `0` tests once. |
| [`Startup.Conditions.<Name>.Interval`](../../configuration-reference.md#startup-tasks) | number | `2` | Seconds between two tests. |

The shipped `Network` condition is met when a network connection profile reports Internet connectivity (IPv4 or IPv6); it sends nothing.

## Decisions

1. What tells you the thing is up?
    - Options: Any command line whose output is truthy when it is: `$true`, a non-empty string, a process object (`Get-Process myservice -ErrorAction SilentlyContinue`). For a program whose exit code is the answer, discard its output and end with the comparison: `'myvpn status *> $null; $LASTEXITCODE -eq 0'`. Write the test in single quotes so `$` is not expanded when the file is read. Errors the test writes are not shown.
    - Default: Only `Network` exists.
    - More detail: [`Startup.Conditions`](../../configuration-reference.md#startup-tasks)
2. How long is it worth waiting?
    - Options: `Timeout` in seconds. A task whose condition is not met in time is skipped and, having written no stamp, is due again at the next trigger. A run with the `TerminalOpen` trigger ignores the timeout: it tests once and never waits.
    - Default: `60`.
    - More detail: [`Startup.Conditions`](../../configuration-reference.md#startup-tasks)
3. How often should it look?
    - Options: `Interval` in seconds, greater than zero. A cheap test can run every second; one that starts a program is better left at the default.
    - Default: `2`.
    - More detail: [`Startup.Conditions`](../../configuration-reference.md#startup-tasks)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`Startup.Conditions` is a hashtable, so a condition of yours is added beside `Network`, and writing only `Network = @{ Timeout = 120 }` changes that one value of the shipped entry.

## Steps Overview

1. Set `Startup.Conditions`
2. Reload and confirm the merge landed

## Step 1: Set `Startup.Conditions`

```powershell
Startup = @{
    Conditions = @{
        MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back: your condition and the shipped `Network` should both be there.

```powershell
Reload-PowerShellProfile
$global:Configuration.Startup.Conditions
```

## Verification

Read-only checks: each runs the condition's own test once and changes nothing else.

```powershell
$global:Configuration.Startup.Conditions.Keys

# Is it met right now? One test, no waiting
Test-StartupCondition -Name Network -NoWait
Test-StartupCondition -Name MyVpn -NoWait

# Which conditions a trigger's tasks would still wait for
Invoke-StartupTasks -Trigger SignIn -WhatIf | Format-Table Name, Status, Reason
```

An unknown name, an entry without `Test` and a test that does not parse are each reported and count as not met.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Startup = @{
        Conditions = @{
            Network = @{ Timeout = 120 }
            MyVpn   = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 }
        }
    }
}
```

## Related

- [`Test-StartupCondition` in the Workflow module reference](../../../modules/workflow.md#test-startupcondition) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [`Invoke-StartupTasks`](Invoke-StartupTasks.md) - the walkthrough: a condition, a task that requires it, and the rehearsal
- [`Invoke-StartupTask`](Invoke-StartupTask.md) - the caller: waits for every `Requires` condition before the command runs
- [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md) - rejects a task whose `Requires` names no condition
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section

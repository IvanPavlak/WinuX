# Register-StartupTaskPromptCheck

Makes a shell that stays open into the next day run its once-a-day startup tasks at its first prompt after the day starts.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It acts on the tasks of [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) that have the `TerminalOpen` trigger and `Frequency = "OncePerDay"`, read through [`Get-StartupTaskDefinitions`](Get-StartupTaskDefinitions.md) and configured on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide. With no such task (valid, enabled, in this machine's scope) it does nothing.

## Usage

```powershell
# Not called by hand: the profile calls it after the first prompt, right before Invoke-StartupTasks -Trigger TerminalOpen
Register-StartupTaskPromptCheck

# When this shell looks again
$global:WinuXStartupTaskPrompt.NextCheck
```

It wraps the current `prompt` function with [`Invoke-StartupTaskPromptCheck`](Invoke-StartupTaskPromptCheck.md) and records the next day boundary - the earliest `DayStartHour` among those tasks, today or tomorrow. Until then every prompt costs one time comparison. Calling it again (`Reload-PowerShellProfile`) never wraps the prompt twice. It does nothing in a shell that belongs to a startup task.

It replaces the deprecated [`Register-RepositoryUpdatePromptCheck`](../git/Register-RepositoryUpdatePromptCheck.md).

## Related

- [`Register-StartupTaskPromptCheck` in the Workflow module reference](../../../modules/workflow.md#register-startuptaskpromptcheck) - parameters, usage and behaviour
- [`Invoke-StartupTaskPromptCheck`](Invoke-StartupTaskPromptCheck.md) - the prompt it installs
- [`Invoke-StartupTasks`](Invoke-StartupTasks.md) - what the first prompt of a new day runs
- [Workflow configuration guides](README.md) - every guide for this module

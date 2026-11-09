# New-StartupTaskShellCommand

Builds the self-contained PowerShell text a new shell runs for a startup task, or for the startup runner itself - the one command line the scheduled task, a task's tab and an Administrator relaunch all agree on.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The parameters it packs into the text come from a [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) entry, configured on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide.

## Usage

```powershell
# The text of a tab that runs MyTask and closes itself when it succeeded
New-StartupTaskShellCommand -Arguments @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace" } -TaskShell -ExitOn Succeeded

# What the sign-in scheduled task hands to pwsh -EncodedCommand
New-StartupTaskShellCommand -Command "Invoke-StartupTasks -Trigger SignIn" -LoadProfile -ExitAlways -Encoded
```

`-LoadProfile` adds a prelude for a shell started with `pwsh -NoProfile`: it sets `WINUX_STARTUP_SKIP` to `-SkipStage` (by default every interactive profile stage: `Schema`, `Greeting`, `PSReadLine`, `Terminal-Icons`, `PSReadLineOptions`, `OhMyPosh`, `PowerPlan`, `LogMaintenance`, `StartupTasks`), dot-sources the profiles PowerShell itself would have loaded, and removes the variable again. That gives the shell the configuration, the modules and the aliases without the greeting and the prompt theme. `-Arguments` travel as JSON inside the text, so nothing depends on a variable of the calling shell.

## Related

- [`New-StartupTaskShellCommand` in the Workflow module reference](../../../modules/workflow.md#new-startuptaskshellcommand) - parameters, usage and behaviour
- [`Start-StartupTaskShell`](Start-StartupTaskShell.md), [`Invoke-StartupTask`](Invoke-StartupTask.md) and [`Set-StartupTasks`](../bootstrap/Set-StartupTasks.md) - the three callers
- [`Test-StartupStage`](../helper/Test-StartupStage.md) - the stage guard `WINUX_STARTUP_SKIP` drives
- [Workflow configuration guides](README.md) - every guide for this module

# Complete-ObsidianWorkspaceLoad

Finishes the Obsidian workspace load that `Open-Obsidian -Deferred` handed back to the flow: polls the CLI if Obsidian was only just launched, runs the checked load, prints the success line.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Complete-ObsidianWorkspaceLoad -CliPath (Get-ObsidianCliPath) -Vault Obsidian -Name Server -ColdStart
```

`Open-Obsidian -Deferred` registers this call through `Register-DeferredAction`, and `Open-Workspace` runs it with every other queued tail through `Complete-DeferredActions`, immediately before the `Set-WorkspaceWindowLayout` action. Pass `-ColdStart` only when Obsidian was launched by the same open and may still be starting.

It has to run before the layout begins waiting on windows rather than during it, because loading a workspace retitles Obsidian's window and the wait holds a window stable only while its title stops changing.

## Related

- [`Complete-ObsidianWorkspaceLoad` in the Application module reference](../../../modules/application.md#complete-obsidianworkspaceload) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function that queues this call
- [`Register-DeferredAction`](../helper/Register-DeferredAction.md) and [`Complete-DeferredActions`](../helper/Complete-DeferredActions.md) - the queue and its drain
- [`Invoke-ObsidianWorkspaceLoad`](Invoke-ObsidianWorkspaceLoad.md) - the checked load it performs

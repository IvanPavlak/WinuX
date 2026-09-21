# Register-DeferredAction

Queues a tail of work an opener hands back to the flow that called it, with the arguments it needs, to run when the flow drains the queue with `Complete-DeferredActions`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Register-DeferredAction -Label "Obsidian workspace [$Name]" -Parameters @{ CliPath = $cli; Vault = $vault; Name = $Name; ColdStart = $true } -Action {
	param([string]$CliPath, [string]$Vault, [string]$Name, [bool]$ColdStart)
	Complete-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name -ColdStart:$ColdStart
}
```

An action that declares a `-Deferred` switch receives it from `Open-Workspace` and is expected to launch its application, register the slow remainder here, and return. The scriptblock keeps the session state it was written in, so the registering module's own functions resolve when the flow runs it. The parameters are copied at registration, so the caller's locals may go out of scope.

## Related

- [`Register-DeferredAction` in the Helper module reference](../../../modules/helper.md#register-deferredaction) - parameters, usage and behaviour
- [`Complete-DeferredActions`](Complete-DeferredActions.md) - the drain
- [`Open-Obsidian`](../application/Open-Obsidian.md) - the opener that ships with a deferred tail
- [`Open-Workspace`](../workflow/Open-Workspace.md) - injects `Deferred` and drains before the layout
- [Helper configuration guides](README.md) - every guide for this module

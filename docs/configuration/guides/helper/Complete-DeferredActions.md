# Complete-DeferredActions

Runs every tail `Register-DeferredAction` queued, in registration order, empties the queue, and returns how many ran. A no-op returning `0` when nothing is queued.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$null = Complete-DeferredActions
```

`Open-Workspace` calls it for you: immediately before the `Set-WorkspaceWindowLayout` action, because the layout holds a window stable only while its title stops changing and a queued tail may retitle one, and again when an action list ends without a layout action. A flow that lets openers register must drain, or a tail queued by one open would run inside the next.

The queue is cleared before the first tail runs, and a tail that throws is reported as a warning under its label while the tails behind it still run.

## Related

- [`Complete-DeferredActions` in the Helper module reference](../../../modules/helper.md#complete-deferredactions) - parameters, usage and behaviour
- [`Register-DeferredAction`](Register-DeferredAction.md) - what fills the queue
- [`Open-Workspace`](../workflow/Open-Workspace.md) - the flow that drains it
- [Helper configuration guides](README.md) - every guide for this module

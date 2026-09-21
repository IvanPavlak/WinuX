# Invoke-ObsidianWorkspaceLoad

Loads a saved Obsidian workspace through the CLI, returning an object whose `Loaded` says whether the CLI accepted it, `Refusal` names the line that refused, and `Message` carries the warning with its fix. The warning is written unless `-Silent`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$load = Invoke-ObsidianWorkspaceLoad -CliPath (Get-ObsidianCliPath) -Vault Obsidian -Name Server
$load.Loaded
```

The one checked `workspace:load` call. The CLI answers some requests instead of doing the work, most often `Command line interface is not enabled` on a machine where the per-machine toggle is off; run `Enable-ObsidianCli` with Obsidian closed to fix that.

## Related

- [`Invoke-ObsidianWorkspaceLoad` in the Application module reference](../../../modules/application.md#invoke-obsidianworkspaceload) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves
- [`Enable-ObsidianCli`](Enable-ObsidianCli.md) - turns the CLI on when it refused the load

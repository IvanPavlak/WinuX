# Invoke-ObsidianWorkspaceLoad

Loads a saved Obsidian workspace through the CLI, returning `$true` when the CLI accepted it and `$false` when it refused, with the refusal and its fix reported.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-ObsidianWorkspaceLoad -CliPath (Get-ObsidianCliPath) -Vault Obsidian -Name Server
```

The one checked `workspace:load` call. The CLI answers some requests instead of doing the work, most often `Command line interface is not enabled` on a machine where the per-machine toggle is off; run `Enable-ObsidianCli` with Obsidian closed to fix that.

## Related

- [`Invoke-ObsidianWorkspaceLoad` in the Application module reference](../../../modules/application.md#invoke-obsidianworkspaceload) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves
- [`Enable-ObsidianCli`](Enable-ObsidianCli.md) - turns the CLI on when it refused the load

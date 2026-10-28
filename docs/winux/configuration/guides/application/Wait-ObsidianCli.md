# Wait-ObsidianCli

Polls the Obsidian CLI (`obsidian vault=<Vault> workspaces`) until it reaches the running vault or the timeout elapses, returning `$true` or `$false`. Defaults: 10 seconds, one probe every 200 ms.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-ObsidianCli -CliPath (Get-ObsidianCliPath) -Vault Obsidian -TimeoutSeconds 10
```

Returns as soon as the CLI stops answering `The CLI is unable to find Obsidian`, about half a second after a detached launch; the timeout only matters on a slow start.

## Related

- [`Wait-ObsidianCli` in the Application module reference](../../../modules/application.md#wait-obsidiancli) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

# Invoke-ObsidianCli

Runs one Obsidian CLI command in a hidden console with both output streams redirected, and returns the output lines. A launch failure is returned as a single `CLI call failed: ...` line rather than thrown.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-ObsidianCli -CliPath (Get-ObsidianCliPath) -Arguments @("vault=Obsidian", "workspaces")
```

Arguments follow the CLI's own `parameter=value` shape with `vault=<name>` first; see the Obsidian CLI help for the full command list. The hidden console is deliberate: `Obsidian.com` prints its argument echo and callback log to whatever console it is attached to, past any stream redirection.

## Related

- [`Invoke-ObsidianCli` in the Application module reference](../../../modules/application.md#invoke-obsidiancli) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

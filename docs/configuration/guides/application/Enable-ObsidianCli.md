# Enable-ObsidianCli

Turns on the Obsidian command line interface for this machine by setting `"cli": true` in `%APPDATA%\obsidian\obsidian.json`, the file Obsidian also keeps its vault list in. Refuses while Obsidian is running, because Obsidian rewrites that file on every settings change and would discard the flag.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
# Obsidian must be closed
Enable-ObsidianCli

# Show what would change without writing
Enable-ObsidianCli -WhatIf
```

The toggle is Obsidian application state, not vault state: enabling it on one machine does nothing for the next one, even with the vault's `.obsidian` folder synced. `Open-Obsidian` cannot load a workspace until the flag is set on the machine it runs on; when it is not, the CLI answers `Command line interface is not enabled` and `Open-Obsidian` reports that instead of a loaded workspace. The same toggle is Settings > General > Advanced > Command line interface inside Obsidian (Settings > General > Command line interface before Obsidian 1.13).

A missing `obsidian.json` means Obsidian has never been started on this machine; start it once and run the function again. No PATH change is part of this: `Get-ObsidianCliPath` finds `Obsidian.com` beside `Obsidian.exe`, and `AutoPathAdditions` can add the folder for calling `obsidian` yourself.

## Related

- [`Enable-ObsidianCli` in the Application module reference](../../../modules/application.md#enable-obsidiancli) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

# Start-ObsidianDetached

Launches Obsidian for a vault through WMI (`Win32_Process.Create`) so the new process owns no console and survives the terminal that started it. Falls back to `Start-Process "obsidian://open?vault=<Vault>"` when the executable cannot be located or WMI refuses.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-ObsidianDetached -Vault Obsidian
```

The vault name is the one `Open-Obsidian` derives from `PathTemplates.ObsidianDirectory` or reads from `Obsidian.Vault`; both are documented in [Open-Obsidian](Open-Obsidian.md). Electron attaches to the console of the process that launched it, which is why a plain `Start-Process` from a terminal would close Obsidian together with that terminal.

## Related

- [`Start-ObsidianDetached` in the Application module reference](../../../modules/application.md#start-obsidiandetached) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

# Get-ObsidianWorkspaceNames

Reads the saved Obsidian workspace names (the core Workspaces plugin) from `<VaultDirectory>\.obsidian\workspaces.json`. Returns an empty array for an empty directory, a missing file or a file that does not parse.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ObsidianWorkspaceNames -VaultDirectory $MachineSpecificPaths.ObsidianDirectory
```

The vault directory itself comes from `PathTemplates.ObsidianDirectory`, documented in [Open-Obsidian](Open-Obsidian.md). Reading the file rather than asking the CLI works before Obsidian is running, which is why the implicit same-named match and the `-Select` menu use it.

## Related

- [`Get-ObsidianWorkspaceNames` in the Application module reference](../../../modules/application.md#get-obsidianworkspacenames) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

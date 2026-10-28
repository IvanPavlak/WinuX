# Get-ObsidianCliPath

Resolves the Obsidian command line interface: the `obsidian` command on PATH, else `Obsidian.com` in the default install folder `%LOCALAPPDATA%\Programs\obsidian`. Returns `$null` when neither exists.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ObsidianCliPath
```

The CLI is enabled inside Obsidian under Settings > General > Advanced > Command line interface (Obsidian 1.12.4 or newer) or with [`Enable-ObsidianCli`](Enable-ObsidianCli.md); that step is described in [Open-Obsidian](Open-Obsidian.md#step-1-enable-the-obsidian-command-line-interface). A `$null` result is what makes `Open-Obsidian` fall back to a plain launch. Note that `Obsidian.com` exists beside `Obsidian.exe` whether or not the toggle is on, so a path from this function does not mean the CLI will answer - `Open-Obsidian` checks the answer itself.

## Related

- [`Get-ObsidianCliPath` in the Application module reference](../../../modules/application.md#get-obsidianclipath) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](Open-Obsidian.md) - the function this helper serves

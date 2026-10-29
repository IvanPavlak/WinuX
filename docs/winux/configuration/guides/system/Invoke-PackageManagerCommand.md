# Invoke-PackageManagerCommand

Runs one short winget, scoop or choco command with a time limit and returns its output lines.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-PackageManagerCommand -PackageManager Chocolatey -Arguments "pin", "list", "-r"
Invoke-PackageManagerCommand -PackageManager Scoop -Arguments "hold", "git"
Invoke-PackageManagerCommand -PackageManager WinGet -Arguments "pin", "add", "--id", "Git.Git", "--blocking" -TimeoutSeconds 30
```

## Related

- [`Invoke-PackageManagerCommand` in the System module reference](../../../modules/system.md#invoke-packagemanagercommand) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

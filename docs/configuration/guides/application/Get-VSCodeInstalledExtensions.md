# Get-VSCodeInstalledExtensions

Lists the extensions a VS Code profile has installed, with their versions, through `code --list-extensions --show-versions`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VSCodeInstalledExtensions -Command (Get-VSCodeCliPath) -ProfileName Default
Get-VSCodeInstalledExtensions -Command (Get-VSCodeCliPath) -ProfileName Writing
```

## Related

- [`Get-VSCodeInstalledExtensions` in the Application module reference](../../../modules/application.md#get-vscodeinstalledextensions)
- [Application configuration guides](README.md)

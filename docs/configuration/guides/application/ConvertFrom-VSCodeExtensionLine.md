# ConvertFrom-VSCodeExtensionLine

Parses one line of a VS Code profile's `extensions.txt` into its extension id and optional version pin.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ConvertFrom-VSCodeExtensionLine "publisher.name@1.2.3"
Get-Content extensions.txt | ConvertFrom-VSCodeExtensionLine | Where-Object { $_ }
```

## Related

- [`ConvertFrom-VSCodeExtensionLine` in the Application module reference](../../../modules/application.md#convertfrom-vscodeextensionline)
- [Application configuration guides](README.md)

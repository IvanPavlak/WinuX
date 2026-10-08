# Merge-VSCodeExtensionList

Merges the extensions a VS Code profile has installed into the lines of its `extensions.txt`, keeping comments and pins.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
@(Merge-VSCodeExtensionList -Lines (Get-Content extensions.txt) -Installed (& code --list-extensions))
```

## Related

- [`Merge-VSCodeExtensionList` in the Application module reference](../../../modules/application.md#merge-vscodeextensionlist)
- [Application configuration guides](README.md)

# Get-VSCodeProfileItems

Maps the files of a profile folder in the repository (settings, keybindings, tasks, snippets) onto the files of a VS Code profile.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VSCodeProfileItems -Source C:\Repo\VSCode\Profiles\MyProfile -Location (Get-VSCodeProfileLocation Default)
```

## Related

- [`Get-VSCodeProfileItems` in the Application module reference](../../../modules/application.md#get-vscodeprofileitems)
- [Application configuration guides](README.md)

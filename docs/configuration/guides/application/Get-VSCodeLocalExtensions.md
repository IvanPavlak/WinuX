# Get-VSCodeLocalExtensions

Lists the unpackaged VS Code extensions kept in the repository, with the id, version and link name each one's `package.json` gives.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VSCodeLocalExtensions -Root (Resolve-VSCodeProfilesConfig).Extensions
Get-VSCodeLocalExtensions -Root "C:\Repo\VSCode\Extensions"
```

## Related

- [`Get-VSCodeLocalExtensions` in the Application module reference](../../../modules/application.md#get-vscodelocalextensions)
- [`Install-VSCodeLocalExtensions`](Install-VSCodeLocalExtensions.md) - links what this lists into VS Code
- [Application configuration guides](README.md)

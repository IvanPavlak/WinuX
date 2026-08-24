# Get-DatabaseTypeFromProject

Detects the database type of a .NET project by analyzing its project name, project file path, and/or EF Core ModelSnapshot content.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-DatabaseTypeFromProject -projectName "MyProject.PostgreMigrations"
Get-DatabaseTypeFromProject -projectName "MyProject" -snapshotContent $snapshot
```

## Related

- [`Get-DatabaseTypeFromProject` in the Helper module reference](../../../modules/helper.md#get-databasetypefromproject) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

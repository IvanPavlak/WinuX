# Get-DbContextFromSnapshot

Extracts the DbContext class name from an EF Core `*ModelSnapshot.cs` file by parsing its `[DbContext(typeof(...))]` attribute, so the value can be passed to `dotnet ef` via `--context`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-DbContextFromSnapshot -SnapshotPath "<DevRoot>\MyProject\Migrations\MyContextModelSnapshot.cs"
```

## Related

- [`Get-DbContextFromSnapshot` in the Helper module reference](../../../modules/helper.md#get-dbcontextfromsnapshot) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

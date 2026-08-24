# Get-EfMigrations

Lists the EF Core migration `.cs` files in a migrations folder, sorted by name (which, because the files are timestamp-prefixed, is chronological order).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-EfMigrations -MigrationFolderPath "<DevRoot>\MyProject\Domain.PostgreMigrations\Migrations"
```

## Related

- [`Get-EfMigrations` in the Helper module reference](../../../modules/helper.md#get-efmigrations) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

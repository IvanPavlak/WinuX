# Resolve-EfMigrationDbContext

Resolves which DbContext (if any) to pass to `dotnet ef` migration commands and whether an explicit `--context` flag is required.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-EfMigrationDbContext -MigrationProject $proj -MigrationsProjectPath "src\MyProject.Migrations" -StartupProjectPath "src\MyProject.Api" -SolutionRoot "<DevRoot>\MySolution"
```

## Related

- [`Resolve-EfMigrationDbContext` in the Helper module reference](../../../modules/helper.md#resolve-efmigrationdbcontext) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

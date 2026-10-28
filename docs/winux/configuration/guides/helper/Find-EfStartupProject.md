# Find-EfStartupProject

Resolves the best EF Core startup project (the one passed to `dotnet ef --startup-project`) for migration commands.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Find-EfStartupProject -SolutionRoot $root -CsprojFiles $csproj -MigrationsProjectPath "src\MyMigrations" -MigrationsProjectFile $projFile
```

## Related

- [`Find-EfStartupProject` in the Helper module reference](../../../modules/helper.md#find-efstartupproject) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

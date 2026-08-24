# Find-EfMigrationProjects

Discovers EF Core migration projects within a solution using two patterns: dedicated migration projects whose name or directory matches `*Migrations*` (e.g.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$csproj = Get-ChildItem -Path <DevRoot>\MySolution -Recurse -Filter "*.csproj" -File
Find-EfMigrationProjects -SolutionRoot <DevRoot>\MySolution -CsprojFiles $csproj
```

## Related

- [`Find-EfMigrationProjects` in the Helper module reference](../../../modules/helper.md#find-efmigrationprojects) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

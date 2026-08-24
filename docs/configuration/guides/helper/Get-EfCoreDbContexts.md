# Get-EfCoreDbContexts

Runs `dotnet ef dbcontext list` for the provided migration/startup project pair and parses the output into unique, design-time discoverable DbContext names.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-EfCoreDbContexts -ProjectPath "src\MyProject.Migrations" -StartupProjectPath "src\Api" -WorkingDirectory "<DevRoot>\MySolution"
```

## Related

- [`Get-EfCoreDbContexts` in the Helper module reference](../../../modules/helper.md#get-efcoredbcontexts) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

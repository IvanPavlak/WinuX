# Find-Item

A robust recursive search for files or directories by pattern with bidirectional search capability: it searches both downward (into subdirectories) and upward (through parent directories) until it finds a match.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Find-Item -Pattern "*.sln"
Find-Item -Pattern "*.csproj" -NameFilter "Domain"
Find-Item -Pattern "*" -SearchTarget "Directory" -NameFilter "Database" -MaxDownwardDepth 3
```

## Related

- [`Find-Item` in the Helper module reference](../../../modules/helper.md#find-item) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

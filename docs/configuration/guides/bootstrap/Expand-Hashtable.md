# Expand-Hashtable

Recursively walks a hashtable (or nested array, list, or string) and replaces placeholder tokens with actual values: `{Dev}` -> development path, `{User}` -> user path, `{MachineType}` -> machine type name, `{RepoRoot}` -> WinuX repository root, and `{AppData}` / `%APPDATA%` / `%ALLUSERSPROFILE%` / `%LOCALAPPDATA%` -> their environment paths.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Expand-Hashtable -Source $config -DevPath "<DevRoot>" -UserPath "C:\Users\<User>" -MachineTypeName "MyMachine"
```

## Related

- [`Expand-Hashtable` in the Bootstrap module reference](../../../modules/bootstrap.md#expand-hashtable) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module

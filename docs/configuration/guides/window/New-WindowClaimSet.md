# New-WindowClaimSet

Builds the one object that says which windows a layout pass may claim (existing, protected, excluded, candidate and pinned windows), handed to `Set-WindowLayouts` and `Wait-ForWorkspaceWindows` as `-Claims`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$claims = New-WindowClaimSet -Existing $existingHandles -Protected $protection.WindowHandles
New-WindowClaimSet -Existing $existingHandles -SkipExisting
```

## Related

- [`New-WindowClaimSet` in the Window module reference](../../../modules/window.md#new-windowclaimset) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module

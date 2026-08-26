# Unpin-TaskbarApps

Clears all taskbar pins and applies an XML layout policy that prevents further taskbar modifications.

> [!NOTE]
> An existing **real** taskbar layout XML (which may encode your own hand-pinned arrangement) is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/TaskbarLayout/<timestamp>/`) before the empty layout replaces it; if the backup cannot be taken the write is skipped.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Unpin-TaskbarApps
Unpin-TaskbarApps -SkipExplorerRestart
```

## Related

- [`Unpin-TaskbarApps` in the System module reference](../../../modules/system.md#unpin-taskbarapps) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module

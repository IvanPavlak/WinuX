# Resolve-HostingTerminalTab

Identifies the Windows Terminal window and tab the current shell is running in, by walking up the parent-process chain until a `WindowsTerminal` parent appears.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$own = Resolve-HostingTerminalTab
```

## Related

- [`Resolve-HostingTerminalTab` in the Helper module reference](../../../modules/helper.md#resolve-hostingterminaltab) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module

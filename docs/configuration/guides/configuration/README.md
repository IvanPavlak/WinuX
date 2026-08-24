# Configuration Module Configuration Guides

One configuration guide per exported function of the `Configuration` module, which covers programmatic edits to `Configuration.psd1` itself - the `Add-*` writers, the app-list overlay writer, and the schema and section primitives they are built on. 10 functions in total: 8 read configuration and 2 do not.

The [Configuration module reference](../../../modules/configuration.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Add-BrowserGroup` | `BrowserGroups` | [Add-BrowserGroup](Add-BrowserGroup.md) |
| `Add-Project` | `ProjectActions`, `Projects`, `ProjectTerminals`, `RunnableProjects` | [Add-Project](Add-Project.md) |
| `Add-SymbolicLink` | `PathTemplates.SymbolicLinks` | [Add-SymbolicLink](Add-SymbolicLink.md) |
| `Add-WindowLayout` | `SimpleLayoutWorkspaces` | [Add-WindowLayout](Add-WindowLayout.md) |
| `Add-Workspace` | `WorkspaceActions`, `Workspaces` | [Add-Workspace](Add-Workspace.md) |
| `Find-ConfigurationSection` | caller-supplied | [Find-ConfigurationSection](Find-ConfigurationSection.md) |
| `Save-AppCsvOverlay` | `BootstrapConfig`, `ValidMachineTypes` | [Save-AppCsvOverlay](Save-AppCsvOverlay.md) |
| `Test-ConfigurationSchema` | caller-supplied | [Test-ConfigurationSchema](Test-ConfigurationSchema.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[ConvertTo-ActionString](ConvertTo-ActionString.md), [Test-ConfigurationKeyPath](Test-ConfigurationKeyPath.md)

## Related

- [Configuration module reference](../../../modules/configuration.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module

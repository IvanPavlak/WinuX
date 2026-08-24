# Bootstrap Module Configuration Guides

One configuration guide per exported function of the `Bootstrap` module, which covers the provisioning entry point and the configuration loader: machine detection, path expansion, step resolution, and the app-list read path.

The [Bootstrap module reference](../../../modules/bootstrap.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Bootstrap` | `BootstrapConfig`, `DefaultDisplayLanguage`, `DefaultKeyboardLayoutSet`, `DefaultLocale`, `DefaultMachineType`, `DefaultNerdFont`, `GitConfig` | [Bootstrap](Bootstrap.md) |
| `DetermineMachineType` | `HostnameToMachineType`, `ValidMachineTypes` | [DetermineMachineType](DetermineMachineType.md) |
| `Expand-ConfigPaths` | `BasePaths`, `MachineOverrides`, `PathTemplates` | [Expand-ConfigPaths](Expand-ConfigPaths.md) |
| `Import-AppCsv` | `BootstrapConfig.DataFiles`, `PathTemplates.Projects.Self` | [Import-AppCsv](Import-AppCsv.md) |
| `Invoke-PersonalSteps` | `BootstrapConfig` | [Invoke-PersonalSteps](Invoke-PersonalSteps.md) |
| `Load-PathConfiguration` | `BasePaths`, `DefaultMachineType`, `HostnameToMachineType`, `Universal` | [Load-PathConfiguration](Load-PathConfiguration.md) |
| `Resolve-BootstrapSteps` | `BootstrapConfig` | [Resolve-BootstrapSteps](Resolve-BootstrapSteps.md) |
| `Resolve-PackageManagers` | `PackageManagers` | [Resolve-PackageManagers](Resolve-PackageManagers.md) |
| `Test-MachineTypeScope` | `ValidMachineTypes` | [Test-MachineTypeScope](Test-MachineTypeScope.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Expand-Hashtable](Expand-Hashtable.md), [Initialize-Configuration](Initialize-Configuration.md), [Install-WinGetPackageManager](Install-WinGetPackageManager.md), [Merge-Hashtable](Merge-Hashtable.md)

## Related

- [Bootstrap module reference](../../../modules/bootstrap.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module

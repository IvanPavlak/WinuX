# Application Module Configuration Guides

One configuration guide per exported function of the `Application` module, which covers installing and launching applications - package-manager installs, browsers, editors, and the WSL tab helpers. 43 functions in total: 19 read configuration and 24 do not.

The [Application module reference](../../../modules/application.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Create-CondaEnvironments` | `BootstrapConfig` | [Create-CondaEnvironments](Create-CondaEnvironments.md) |
| `Get-VSCodeWorkspaceNames` | `PathTemplates.Projects.Self` | [Get-VSCodeWorkspaceNames](Get-VSCodeWorkspaceNames.md) |
| `Install-ChocolateyApps` | `BootstrapConfig.DataFiles`, `PackageManagers` | [Install-ChocolateyApps](Install-ChocolateyApps.md) |
| `Install-DotnetEf` | `DotnetEFVersion` | [Install-DotnetEf](Install-DotnetEf.md) |
| `Install-ScoopApps` | `BootstrapConfig.DataFiles`, `PackageManagers` | [Install-ScoopApps](Install-ScoopApps.md) |
| `Install-WingetApps` | `BootstrapConfig.DataFiles` | [Install-WingetApps](Install-WingetApps.md) |
| `Open-Acrobat` | `AcrobatGroups`, `AcrobatPdfGroups` | [Open-Acrobat](Open-Acrobat.md) |
| `Open-Browser` | `BrowserGroups`, `Universal` | [Open-Browser](Open-Browser.md) |
| `Open-LeagueOfLegends` | `Universal` | [Open-LeagueOfLegends](Open-LeagueOfLegends.md) |
| `Open-NotepadPlusPlus` | `Universal` | [Open-NotepadPlusPlus](Open-NotepadPlusPlus.md) |
| `Open-Steam` | `Universal` | [Open-Steam](Open-Steam.md) |
| `Open-VisualStudio` | `Universal`, `VisualStudioSolutions` | [Open-VisualStudio](Open-VisualStudio.md) |
| `Open-VSCode` | `VSCodeProjects` | [Open-VSCode](Open-VSCode.md) |
| `Open-VSCodeWorkspace` | `PathTemplates.Projects.Self` | [Open-VSCodeWorkspace](Open-VSCodeWorkspace.md) |
| `Open-WSLTab` | `DefaultWSLDistribution` | [Open-WSLTab](Open-WSLTab.md) |
| `Start-Application` | `Universal` | [Start-Application](Start-Application.md) |
| `Start-Win11Debloat` | `BootstrapConfig` | [Start-Win11Debloat](Start-Win11Debloat.md) |
| `Test-BrowserGroupAlreadyOpen` | `BrowserGroupMatching` | [Test-BrowserGroupAlreadyOpen](Test-BrowserGroupAlreadyOpen.md) |
| `Update-Win11DebloatVendor` | `PathTemplates.Projects.Self`, `BootstrapConfig` | [Update-Win11DebloatVendor](Update-Win11DebloatVendor.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add Browser Group](add-browser-group.md) - browser groups, nesting, unique names, search and per-browser selection

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Install-ChocolateyPackageManager](Install-ChocolateyPackageManager.md), [Install-FromExecutable](Install-FromExecutable.md), [Install-PowerShellModules](Install-PowerShellModules.md), [Install-ScoopPackageManager](Install-ScoopPackageManager.md), [Invoke-Browser](Invoke-Browser.md), [Open-ClaudeDesktop](Open-ClaudeDesktop.md), [Open-DBeaver](Open-DBeaver.md), [Open-Discord](Open-Discord.md), [Open-Docker](Open-Docker.md), [Open-FoundryVTT](Open-FoundryVTT.md), [Open-Obsidian](Open-Obsidian.md), [Open-Outlook](Open-Outlook.md), [Open-RiseupVPN](Open-RiseupVPN.md), [Open-SecureBrowser](Open-SecureBrowser.md), [Open-Slack](Open-Slack.md), [Open-TeamViewer](Open-TeamViewer.md), [Open-Terminal](Open-Terminal.md), [Open-VirtualBox](Open-VirtualBox.md), [Open-WhatsApp](Open-WhatsApp.md), [Start-FancyZones](Start-FancyZones.md), [Start-MicrosoftActivationScripts](Start-MicrosoftActivationScripts.md), [Stop-PowerToysCompletely](Stop-PowerToysCompletely.md), [Test-ProjectAlreadyOpen](Test-ProjectAlreadyOpen.md), [Wait-BrowserWindowReady](Wait-BrowserWindowReady.md)

## Related

- [Application module reference](../../../modules/application.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module

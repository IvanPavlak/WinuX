# System Module Configuration Guides

One configuration guide per exported function of the `System` module, which covers the machine itself: registry-driven Windows settings, locale and keyboard, theme and wallpaper, taskbar, power, WSL provisioning, and symbolic links.

The [System module reference](../../../modules/system.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Clear-WhatsAppLocalStorage` | `Universal` | [Clear-WhatsAppLocalStorage](Clear-WhatsAppLocalStorage.md) |
| `Configure-NerdFont` | `DefaultNerdFont`, `NerdFonts`, `Universal` | [Configure-NerdFont](Configure-NerdFont.md) |
| `Configure-PostgreSqlPasswords` | `PostgreSqlPasswords` | [Configure-PostgreSqlPasswords](Configure-PostgreSqlPasswords.md) |
| `Configure-Taskbar` | `HostnameToMachineType`, `TaskbarConfiguration`, `Universal` | [Configure-Taskbar](Configure-Taskbar.md) |
| `Configure-WSL` | `DefaultWSLDistribution`, `DefaultWSLUsername` | [Configure-WSL](Configure-WSL.md) |
| `Configure-WSLSSH` | `DefaultWSLDistribution` | [Configure-WSLSSH](Configure-WSLSSH.md) |
| `Deploy-CoreAiRules` | `DefaultWSLDistribution` | [Deploy-CoreAiRules](Deploy-CoreAiRules.md) |
| `Determine-DotnetDependencies` | `DotnetProjectsSearchPath` | [Determine-DotnetDependencies](Determine-DotnetDependencies.md) |
| `Get-PinnedApps` | `BootstrapConfig.DataFiles` | [Get-PinnedApps](Get-PinnedApps.md) |
| `Initialize-OhMyPosh` | `Universal` | [Initialize-OhMyPosh](Initialize-OhMyPosh.md) |
| `Initialize-WSLEnvironment` | `DefaultWSLDistribution`, `Universal` | [Initialize-WSLEnvironment](Initialize-WSLEnvironment.md) |
| `Rebuild-IconCache` | `Universal` | [Rebuild-IconCache](Rebuild-IconCache.md) |
| `Rename-Machine` | `HostnameToMachineType` | [Rename-Machine](Rename-Machine.md) |
| `Resolve-KillAllSteps` | `KillAll` | [Resolve-KillAllSteps](Resolve-KillAllSteps.md) |
| `Resolve-SystemThemeSteps` | `SystemTheme` | [Resolve-SystemThemeSteps](Resolve-SystemThemeSteps.md) |
| `Send-WakeOnLan` | `DefaultWakeOnLanMachine`, `WakeOnLanConfig`, `WakeOnLanMachines` | [Send-WakeOnLan](Send-WakeOnLan.md) |
| `Set-DisplayLanguage` | `DefaultDisplayLanguage`, `DisplayLanguages` | [Set-DisplayLanguage](Set-DisplayLanguage.md) |
| `Set-EnvironmentVariables` | `AutoEnvironmentVariables`, `AutoPathAdditions`, `BasePaths` | [Set-EnvironmentVariables](Set-EnvironmentVariables.md) |
| `Set-ExplorerOptions` | `ExplorerOptions` | [Set-ExplorerOptions](Set-ExplorerOptions.md) |
| `Set-KeyboardLayouts` | `DefaultKeyboardLayoutSet`, `KeyboardLayouts`, `KeyboardLayoutSets` | [Set-KeyboardLayouts](Set-KeyboardLayouts.md) |
| `Set-Locale` | `DefaultLocale`, `Locales` | [Set-Locale](Set-Locale.md) |
| `Set-LockScreenWallpaper` | `WallpaperDarkSettings`, `WallpaperLightSettings` | [Set-LockScreenWallpaper](Set-LockScreenWallpaper.md) |
| `Set-PowerButtonActions` | `PowerButtonActions` | [Set-PowerButtonActions](Set-PowerButtonActions.md) |
| `Set-PowerPlan` | `PowerPlans` | [Set-PowerPlan](Set-PowerPlan.md) |
| `Set-SpecialFolders` | `BasePaths`, `SpecialFolders` | [Set-SpecialFolders](Set-SpecialFolders.md) |
| `Set-SystemTheme` | `Themes` | [Set-SystemTheme](Set-SystemTheme.md) |
| `Set-TaskbarSettings` | `TaskbarSettings` | [Set-TaskbarSettings](Set-TaskbarSettings.md) |
| `Set-VisualEffects` | `VisualEffects` | [Set-VisualEffects](Set-VisualEffects.md) |
| `Set-Wallpaper` | `WallpaperDarkSettings`, `WallpaperLightSettings`, `WallpaperStyles` | [Set-Wallpaper](Set-Wallpaper.md) |
| `SymbolicLinkMaker` | `PathTemplates.SymbolicLinks`, `DefaultWSLDistribution` | [SymbolicLinkMaker](SymbolicLinkMaker.md) |
| `Sync-AppPins` | `BootstrapConfig.DataFiles` | [Sync-AppPins](Sync-AppPins.md) |
| `Terminate-AllBrowserProcesses` | `Universal` | [Terminate-AllBrowserProcesses](Terminate-AllBrowserProcesses.md) |
| `Terminate-AllProcessesByName` | `Universal` | [Terminate-AllProcessesByName](Terminate-AllProcessesByName.md) |
| `Terminate-AllProcessesWithVisibleWindows` | `Universal` | [Terminate-AllProcessesWithVisibleWindows](Terminate-AllProcessesWithVisibleWindows.md) |
| `Test-MachineOnline` | `WakeOnLanConfig` | [Test-MachineOnline](Test-MachineOnline.md) |
| `Test-PowerPlan` | `LaptopChassisTypes` | [Test-PowerPlan](Test-PowerPlan.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Add-WindowsFormsType](Add-WindowsFormsType.md), [Clear-TaskbarPins](Clear-TaskbarPins.md), [Close-BrowserWindows](Close-BrowserWindows.md), [Configure-NuGetConfig](Configure-NuGetConfig.md), [Display-SystemLanguageSettings](Display-SystemLanguageSettings.md), [Enable-DeveloperMode](Enable-DeveloperMode.md), [Get-BrowserTitlePattern](Get-BrowserTitlePattern.md), [Get-BrowserWindowsByTarget](Get-BrowserWindowsByTarget.md), [Get-InstalledApps](Get-InstalledApps.md), [Get-SymbolicLinkEntries](Get-SymbolicLinkEntries.md), [Initialize-Win32BrowserHelperType](Initialize-Win32BrowserHelperType.md), [Invoke-ClearAndFastfetch](Invoke-ClearAndFastfetch.md), [Invoke-TerminateWindowsTerminalTabsExit](Invoke-TerminateWindowsTerminalTabsExit.md), [Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup](Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup.md), [Kill-All](Kill-All.md), [List-Drives](List-Drives.md), [New-WindowsSymbolicLink](New-WindowsSymbolicLink.md), [New-WSLSymbolicLink](New-WSLSymbolicLink.md), [Reload-PowerShellProfile](Reload-PowerShellProfile.md), [Reload-WinuXModules](Reload-WinuXModules.md), [Remove-VirtualDesktops](Remove-VirtualDesktops.md), [Repair-RpcServer](Repair-RpcServer.md), [Restart-Explorer](Restart-Explorer.md), [Restart-Machine](Restart-Machine.md), [Set-CustomExecutionPolicy](Set-CustomExecutionPolicy.md), [Set-ShortcutAumid](Set-ShortcutAumid.md), [Show-PinnedAppsWarning](Show-PinnedAppsWarning.md), [Terminate-WindowsTerminalTabs](Terminate-WindowsTerminalTabs.md), [Test-RpcServerHealth](Test-RpcServerHealth.md), [Test-WindowTitleMatch](Test-WindowTitleMatch.md), [Unpin-TaskbarApps](Unpin-TaskbarApps.md), [Update-DirectoryNames](Update-DirectoryNames.md), [Upgrade-All](Upgrade-All.md)

## Related

- [System module reference](../../../modules/system.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module

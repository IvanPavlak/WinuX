# Window Module Configuration Guides

One configuration guide per exported function of the `Window` module, which covers window placement: FancyZones layouts, virtual desktops, snapping, resizing, and the per-workspace layout files.

The [Window module reference](../../../modules/window.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Apply-FancyZones` | `LayoutNumbers` | [Apply-FancyZones](Apply-FancyZones.md) |
| `Center-Terminal` | `CenterTerminalSizing` | [Center-Terminal](Center-Terminal.md) |
| `Generate-LayoutVisualization` | `ZoneNameMappings` | [Generate-LayoutVisualization](Generate-LayoutVisualization.md) |
| `Get-FancyZone` | `ZoneNameMappings` | [Get-FancyZone](Get-FancyZone.md) |
| `Get-FancyZoneCoordinates` | `PathTemplates.SymbolicLinks`, `LayoutNumbers` | [Get-FancyZoneCoordinates](Get-FancyZoneCoordinates.md) |
| `Get-LayoutMachineType` | `LayoutMachineTypeOverrides`, `SmallDisplayMachineType` | [Get-LayoutMachineType](Get-LayoutMachineType.md) |
| `Get-WindowInsetPercent` | `SnapInsetPercent` | [Get-WindowInsetPercent](Get-WindowInsetPercent.md) |
| `Reset-Windows` | `ResetAllWindowsDefaults` | [Reset-Windows](Reset-Windows.md) |
| `Resolve-LayoutTokens` | `Universal` | [Resolve-LayoutTokens](Resolve-LayoutTokens.md) |
| `Resolve-ResizeWindowsPercent` | `ResizeWindowsPercent` | [Resolve-ResizeWindowsPercent](Resolve-ResizeWindowsPercent.md) |
| `Set-WorkspaceWindowLayout` | `SimpleLayoutWorkspaces`, `LayoutMachineTypeOverrides` | [Set-WorkspaceWindowLayout](Set-WorkspaceWindowLayout.md) |
| `Test-FancyZonesConfiguration` | `LayoutNumbers`, `ZoneNameMappings` | [Test-FancyZonesConfiguration](Test-FancyZonesConfiguration.md) |
| `Update-LayoutSectionHeaders` | `ZoneNameMappings` | [Update-LayoutSectionHeaders](Update-LayoutSectionHeaders.md) |
| `Visualize-Layouts` | `LayoutNumbers`, `ZoneNameMappings` | [Visualize-Layouts](Visualize-Layouts.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Add-PositionedWindow](Add-PositionedWindow.md), [Build-ZoneGridMap](Build-ZoneGridMap.md), [Center-Text](Center-Text.md), [Center-Windows](Center-Windows.md), [Clear-FancyZonesCache](Clear-FancyZonesCache.md), [Clear-MonitorCache](Clear-MonitorCache.md), [Clear-WindowCache](Clear-WindowCache.md), [Confirm-WindowForeground](Confirm-WindowForeground.md), [Confirm-WorkspaceWindowPositions](Confirm-WorkspaceWindowPositions.md), [ConvertTo-InternalDesktopIndex](ConvertTo-InternalDesktopIndex.md), [Ensure-DesktopVisible](Ensure-DesktopVisible.md), [Ensure-VirtualDesktops](Ensure-VirtualDesktops.md), [Ensure-WindowsFormsLoaded](Ensure-WindowsFormsLoaded.md), [Expand-LayoutMonitorCoverage](Expand-LayoutMonitorCoverage.md), [Focus-VirtualDesktop](Focus-VirtualDesktop.md), [Format-CanvasZoneListing](Format-CanvasZoneListing.md), [Format-ZoneContent](Format-ZoneContent.md), [Generate-DynamicVisualization](Generate-DynamicVisualization.md), [Get-ActiveWindowInfo](Get-ActiveWindowInfo.md), [Get-AppliedFancyZonesState](Get-AppliedFancyZonesState.md), [Get-CachedFancyZonesLayouts](Get-CachedFancyZonesLayouts.md), [Get-CachedMonitors](Get-CachedMonitors.md), [Get-CachedWindows](Get-CachedWindows.md), [Get-CurrentLayout](Get-CurrentLayout.md), [Get-DuplicateMonitorEdid](Get-DuplicateMonitorEdid.md), [Get-FancyZonesLayoutsPath](Get-FancyZonesLayoutsPath.md), [Get-InsetWindowBounds](Get-InsetWindowBounds.md), [Get-LayoutDefinition](Get-LayoutDefinition.md), [Get-MonitorInfo](Get-MonitorInfo.md), [Get-MonitorSpecs](Get-MonitorSpecs.md), [Get-NextAvailableDesktopIndex](Get-NextAvailableDesktopIndex.md), [Get-PositionedWindowCount](Get-PositionedWindowCount.md), [Get-VirtualDesktopGuid](Get-VirtualDesktopGuid.md), [Get-WindowDesktopIndex](Get-WindowDesktopIndex.md), [Get-WindowDisplayName](Get-WindowDisplayName.md), [Get-WindowHandle](Get-WindowHandle.md), [Get-WindowModuleDelays](Get-WindowModuleDelays.md), [Get-WorkspaceRerunMirror](Get-WorkspaceRerunMirror.md), [Import-VirtualDesktopModule](Import-VirtualDesktopModule.md), [Initialize-PositionedWindowTracking](Initialize-PositionedWindowTracking.md), [Initialize-WorkspaceWindowLayoutRerun](Initialize-WorkspaceWindowLayoutRerun.md), [Invoke-SingleZoneWindowPlacement](Invoke-SingleZoneWindowPlacement.md), [Move-Windows](Move-Windows.md), [Move-WindowToVirtualDesktop](Move-WindowToVirtualDesktop.md), [Reset-KeyboardModifiers](Reset-KeyboardModifiers.md), [Reset-VirtualDesktopComProxy](Reset-VirtualDesktopComProxy.md), [Reset-VirtualDesktopState](Reset-VirtualDesktopState.md), [Resize-PositionedWindows](Resize-PositionedWindows.md), [Resize-Windows](Resize-Windows.md), [Resolve-CenteredWindowPercent](Resolve-CenteredWindowPercent.md), [Resolve-CenterTerminalSizing](Resolve-CenterTerminalSizing.md), [Resolve-DisplayAwareProfile](Resolve-DisplayAwareProfile.md), [Resolve-MonitorLabel](Resolve-MonitorLabel.md), [Resolve-PositionedWindowHandle](Resolve-PositionedWindowHandle.md), [Resolve-TargetMonitor](Resolve-TargetMonitor.md), [Save-CurrentLayout](Save-CurrentLayout.md), [Set-WindowCacheMaxAge](Set-WindowCacheMaxAge.md), [Set-WindowLayouts](Set-WindowLayouts.md), [Set-WindowModuleDelays](Set-WindowModuleDelays.md), [Set-WindowPosition](Set-WindowPosition.md), [Set-WorkspaceRerunMirror](Set-WorkspaceRerunMirror.md), [Snap-AllWindows](Snap-AllWindows.md), [Test-FancyZonesLayoutApplied](Test-FancyZonesLayoutApplied.md), [Test-PositionedWindow](Test-PositionedWindow.md), [Test-SmallPrimaryDisplay](Test-SmallPrimaryDisplay.md), [Test-VirtualDesktopComHealth](Test-VirtualDesktopComHealth.md), [Validate-Layout](Validate-Layout.md), [Wait-DesktopSwitch](Wait-DesktopSwitch.md), [Wait-ForWorkspaceWindows](Wait-ForWorkspaceWindows.md), [Wait-WindowRect](Wait-WindowRect.md), [Wait-WindowsClosed](Wait-WindowsClosed.md), [Write-WindowInfoBlock](Write-WindowInfoBlock.md)

## Related

- [Window module reference](../../../modules/window.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module

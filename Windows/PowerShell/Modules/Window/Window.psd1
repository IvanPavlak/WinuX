@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Window management functions for FancyZones and Virtual Desktops"
	RootModule        = "Window.psm1"
	FunctionsToExport = @(
		'Add-PositionedWindow',
		'Apply-FancyZones',
		'Build-ZoneGridMap',
		'Center-Terminal',
		'Center-Text',
		'Center-Windows',
		'Clear-FancyZonesCache',
		'Clear-MonitorCache',
		'Clear-WindowCache',
		'Confirm-WindowForeground',
		'Confirm-WorkspaceWindowPositions',
		'ConvertTo-InternalDesktopIndex',
		'Ensure-VirtualDesktops',
		'Ensure-WindowsFormsLoaded',
		'Focus-VirtualDesktop',
		'Format-ZoneContent',
		'Generate-DynamicVisualization',
		'Generate-LayoutVisualization',
		'Get-ActiveWindowInfo',
		'Get-AppliedFancyZonesState',
		'Get-CachedFancyZonesLayouts',
		'Get-CachedMonitors',
		'Get-CachedWindows',
		'Get-CurrentLayout',
		'Get-DuplicateMonitorEdid',
		'Get-FancyZone',
		'Get-FancyZoneCoordinates',
		'Get-LayoutDefinition',
		'Get-MonitorInfo',
		'Get-MonitorSpecs',
		'Get-NextAvailableDesktopIndex',
		'Get-PositionedWindowCount',
		'Get-VirtualDesktopGuid',
		'Get-WindowDisplayName',
		'Get-WindowHandle',
		'Get-WindowModuleDelays',
		'Import-VirtualDesktopModule',
		'Initialize-PositionedWindowTracking',
		'Initialize-WorkspaceWindowLayoutRerun',
		'Move-Windows',
		'Move-WindowToVirtualDesktop',
		'Resize-PositionedWindows',
		'Resize-Windows',
		'Reset-KeyboardModifiers',
		'Reset-Windows',
		'Resolve-CenteredWindowPercent',
		'Resolve-LayoutTokens',
		'Resolve-PositionedWindowHandle',
		'Reset-VirtualDesktopComProxy',
		'Reset-VirtualDesktopState',
		'Save-CurrentLayout',
		'Set-WindowCacheMaxAge',
		'Set-WindowLayouts',
		'Set-WindowModuleDelays',
		'Set-WindowPosition',
		'Set-WorkspaceWindowLayout',
		'Snap-AllWindows',
		'Test-FancyZonesLayoutApplied',
		'Test-PositionedWindow',
		'Test-VirtualDesktopComHealth',
		'Update-LayoutSectionHeaders',
		'Validate-Layout',
		'Visualize-Layouts',
		'Wait-DesktopSwitch',
		'Wait-ForWorkspaceWindows',
		'Wait-WindowRect',
		'Write-WindowInfoBlock',
		'Get-InsetWindowBounds'
	)
	PrivateData       = @{
		PSData = @{
			# Tested dependency versions - update only after full validation
			# See: docs/modules/window.md - Tested Dependency Versions
			TestedDependencies = @{
				'Microsoft.PowerToys' = '0.100.2' # FancyZones: zone layouts, keyboard shortcuts, snap
				'VirtualDesktop'      = '1.5.11'  # PS module: virtual desktop management (MScholtes/PSGallery)
				'PowerShell'          = '7.5.4'   # Runtime environment
				'Windows'             = '25H2'    # OS version (build 26200)
			}
		}
	}
}

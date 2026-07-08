function Visualize-Layouts {
	<#
	.SYNOPSIS
		Generates visual representations of window layouts and adds them as comments to layout files.

	.DESCRIPTION
		Creates ASCII art visualizations of FancyZones layouts showing which processes are assigned
		to each zone. The visualizations are added as commented sections at the top of layout files.
		Layout files are organized in machine-specific subfolders (Laptop, PC, Work) within the
		Layouts directory.

	.PARAMETER Layout
		The name of a specific layout to visualize (e.g., "WinuX_Test", "Example_Test").

	.PARAMETER All
		Process all layout files in the Layouts directory and its machine-specific subfolders.

	.PARAMETER DisplayAvailableLayouts
		When specified, displays all available layout types (Zero, One, Two, etc.) with their zone
		names shown in their respective positions. This helps understand the zone structure of each
		layout type defined in configuration.psd1.

	.PARAMETER Update
		When specified, updates the layout files with the generated visualizations.
		Without this parameter, only displays the visualizations without modifying files.

	.EXAMPLE
		Visualize-Layouts
		# Prompts to select one or more layouts and displays them

	.EXAMPLE
		Visualize-Layouts -Layout "WinuX_PC"
		# Displays visualization for a specific layout

	.EXAMPLE
		Visualize-Layouts -All
		# Displays visualizations for all layouts

	.EXAMPLE
		Visualize-Layouts -All -Update
		# Updates all layout files with their visualizations

	.EXAMPLE
		Visualize-Layouts -DisplayAvailableLayouts
		# Displays all available layout types with their zone names
	#>
	[CmdletBinding(DefaultParameterSetName = 'Interactive')]
	param (
		[Parameter(ParameterSetName = 'Specific', Mandatory = $true)]
		[string]$Layout,

		[Parameter(ParameterSetName = 'All', Mandatory = $false)]
		[switch]$All,

		[Parameter(ParameterSetName = 'ShowLayouts', Mandatory = $false)]
		[switch]$DisplayAvailableLayouts,

		[Parameter(Mandatory = $false)]
		[switch]$Update
	)

	# Handle -DisplayAvailableLayouts parameter
	if ($DisplayAvailableLayouts) {
		Write-LogTitle "Available Layout Types" -BlankLineAfter

		# Check if global configuration is loaded
		if (-not $global:Configuration) {
			Write-LogError "Global configuration not loaded. Please run Load-PathConfiguration first." -NoLeadingNewline
			return
		}

		# Get ZoneNameMappings from global configuration
		$zoneNameMappings = $global:Configuration.ZoneNameMappings

		if (-not $zoneNameMappings -or $zoneNameMappings.Count -eq 0) {
			Write-LogWarning "No zone name mappings found in configuration." -NoLeadingNewline
			return
		}

		# Determine path to custom-layouts.json
		$repoRoot = $null
		if ($global:RepoRoot -and (Test-Path $global:RepoRoot)) {
			$repoRoot = $global:RepoRoot
		}
		else {
			# Navigate from module path
			$currentPath = $PSScriptRoot
			for ($i = 0; $i -lt 5; $i++) {
				$currentPath = Split-Path $currentPath -Parent
			}
			$testPath = Join-Path $currentPath "Windows\FancyZones"
			if (Test-Path $testPath) {
				$repoRoot = $currentPath
			}
		}

		if (-not $repoRoot) {
			Write-LogError "Could not determine WinuX root path." -NoLeadingNewline
			return
		}

		$layoutsJsonPath = Join-Path $repoRoot "Windows\FancyZones\custom-layouts.json"

		if (-not (Test-Path $layoutsJsonPath)) {
			Write-LogError "Layouts file not found: $layoutsJsonPath" -NoLeadingNewline
			return
		}

		# Display each layout with its zone names (sorted numerically, not alphabetically)
		$layoutOrder = @("Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine")
		$sortedLayouts = $layoutOrder | Where-Object { $zoneNameMappings.ContainsKey($_) }

		foreach ($layoutName in $sortedLayouts) {
			Write-Host -ForegroundColor DarkCyan " [$layoutName]`n"

			# Get layout definition from custom-layouts.json
			$layoutDef = Get-LayoutDefinition -LayoutsJsonPath $layoutsJsonPath -LayoutName $layoutName

			if ($null -eq $layoutDef) {
				Write-Host -ForegroundColor Yellow "  => Layout definition not found in $layoutsJsonPath"
				Write-Host ""
				continue
			}

			if ($layoutDef.type -ne "grid") {
				Write-Host -ForegroundColor Yellow "  => Layout type [$($layoutDef.type)] is not supported (only grid layouts are supported)"
				Write-Host ""
				continue
			}

			# Build reverse mapping: zone index -> zone name
			# When multiple names map to same index, prefer the most descriptive (longest) name
			# e.g., "Bottom-Right" over "Right", "Far-Left" over "Left"
			$zoneIndexToName = @{}
			foreach ($name in $zoneNameMappings[$layoutName].Keys) {
				$index = $zoneNameMappings[$layoutName][$name]
				# Prefer longer/more descriptive names for clarity in visualization
				if (-not $zoneIndexToName.ContainsKey($index) -or $name.Length -gt $zoneIndexToName[$index].Length) {
					$zoneIndexToName[$index] = $name
				}
			}

			# Generate visualization with zone names (no actual content)
			$visualization = Generate-DynamicVisualization `
				-LayoutInfo $layoutDef.info `
				-ZoneContent @{} `
				-ZoneNames $zoneIndexToName

			if ($visualization) {
				Write-Host -ForegroundColor White $visualization
				Write-Host ""
			}
		}

		Write-LogSuccess "Display complete!" -NoLeadingNewline
		return
	}

	if ($Update) {
		Write-LogTitle "Updating Layout Visualizations" -BlankLineAfter
	}
	else {
		Write-LogTitle "Displaying Layout Visualizations" -BlankLineAfter
	}

	$layoutsDir = Join-Path $PSScriptRoot "..\Layouts"

	if (-not (Test-Path $layoutsDir)) {
		Write-LogError "Layouts directory not found: $layoutsDir"
		return
	}

	# Get all layout files (search recursively in machine-specific folders: Laptop, PC, Work)
	$layoutFiles = Get-ChildItem -Path $layoutsDir -Filter "*.psd1" -Recurse

	if ($layoutFiles.Count -eq 0) {
		Write-LogWarning "No layout files found in $layoutsDir"
		return
	}

	# Determine which files to process
	$filesToProcess = @()

	if ($PSCmdlet.ParameterSetName -eq 'All') {
		$filesToProcess = $layoutFiles
	}
	elseif ($PSCmdlet.ParameterSetName -eq 'Specific') {
		$layoutFile = $layoutFiles | Where-Object { $_.BaseName -eq $Layout }
		if (-not $layoutFile) {
			Write-LogError "Layout '$Layout' not found!"
			Write-LogStep "Available layouts:"
			$layoutFiles | ForEach-Object { Write-LogStep "  - $($_.BaseName)" -NoLeadingNewline }
			return
		}
		$filesToProcess = @($layoutFile)
	}
	else {
		# Interactive mode
		$layoutNames = $layoutFiles | ForEach-Object { $_.BaseName }
		$layoutNames += "All"

		$selection = Resolve-Selection `
			-OptionList $layoutNames `
			-MenuTitle "[Select Layout(s) to Visualize]" `
			-AllowMultipleSelections

		if ($null -eq $selection -or $selection.Count -eq 0) {
			Write-LogWarning "No layouts selected"
			return
		}

		if ($selection -contains "All") {
			$filesToProcess = $layoutFiles
		}
		else {
			$filesToProcess = $layoutFiles | Where-Object { $selection -contains $_.BaseName }
		}
	}

	# Process each selected file
	foreach ($file in $filesToProcess) {
		Write-Host -ForegroundColor DarkCyan " [$($file.BaseName)]`n"

		try {
			$config = Import-PowerShellDataFile -Path $file.FullName

			if (-not $config.Layout) {
				Write-Host -ForegroundColor Yellow "  => No Layout configuration found, skipping..."
				continue
			}

			# Validate layout configuration
			$validationResult = Validate-Layout -Config $config -LayoutName $file.BaseName

			# Display warnings
			if ($validationResult.Warnings.Count -gt 0) {
				$validationResult.Warnings | ForEach-Object {
					Write-Host -ForegroundColor Yellow "  => Warning: $_"
				}
			}

			# Display errors and skip if validation failed
			if (-not $validationResult.IsValid) {
				Write-Host -ForegroundColor Red "  => Validation Errors:"
				$validationResult.Errors | ForEach-Object {
					Write-Host -ForegroundColor Red "  $_"
				}
				Write-Host -ForegroundColor Yellow "  => Skipping due to validation errors..."
				continue
			}

			# Group windows by DesktopNumber first, then by Monitor
			$desktopGroups = $config.Layout | Group-Object -Property DesktopNumber | Sort-Object { [int]$_.Name }

			# Generate visualizations for each desktop and monitor
			$visualizations = @()

			foreach ($desktopGroup in $desktopGroups) {
				$desktopNumber = [int]$desktopGroup.Name
				$desktopWindows = $desktopGroup.Group

				# Group by Monitor within this desktop
				$monitorGroups = $desktopWindows | Group-Object -Property Monitor | Sort-Object {
					# Sort so Primary comes first, then Secondary, then others
					if ($_.Name -eq "Primary") { 0 }
					elseif ($_.Name -eq "Secondary") { 1 }
					else { 2 }
				}

				foreach ($monitorGroup in $monitorGroups) {
					$monitorName = $monitorGroup.Name
					$monitorWindows = $monitorGroup.Group

					# Resolve layout type from Monitors section
					if ($config.Monitors -and
						$config.Monitors.ContainsKey($monitorName) -and
						$config.Monitors[$monitorName].VirtualDesktopLayouts -and
						$config.Monitors[$monitorName].VirtualDesktopLayouts.ContainsKey($desktopNumber)) {
						$layoutType = $config.Monitors[$monitorName].VirtualDesktopLayouts[$desktopNumber]
					}
					else {
						Write-Host -ForegroundColor Yellow "  => Could not resolve layout for Monitor='$monitorName' Desktop=$desktopNumber, skipping..."
						continue
					}

					# Generate visualization
					$visualization = Generate-LayoutVisualization `
						-LayoutType $layoutType `
						-Windows $monitorWindows `
						-DesktopNumber $desktopNumber `
						-MonitorName $monitorName

					if ($visualization) {
						$visualizations += $visualization
					}
				}
			}

			if ($visualizations.Count -eq 0) {
				Write-Host -ForegroundColor Yellow "  => No visualizations generated, skipping..."
				continue
			}

			for ($i = 0; $i -lt $visualizations.Count; $i++) {
				Write-Host -ForegroundColor White $visualizations[$i]
				Write-Host ""
			}

			# Update the layout file if -Update is specified
			if ($Update) {
				# Read the original file content
				$originalContent = Get-Content -Path $file.FullName -Raw

				# Remove existing visualization block if present
				$contentWithoutVisualization = $originalContent -replace '(?s)^<#\s*LAYOUT VISUALIZATION.*?#>\s*\r?\n', ''

				# Create the new visualization block
				$visualizationBlock = "<#`nLAYOUT VISUALIZATION`n" + "=" * 80 + "`n"
				$visualizationBlock += "This shows how windows are arranged across all virtual desktops and monitors.`n"
				$visualizationBlock += "Organized by: Virtual Desktop > Monitor (Primary, Secondary, etc.) > Layout Type`n"
				$visualizationBlock += "=" * 80 + "`n`n"

				for ($i = 0; $i -lt $visualizations.Count; $i++) {
					$visualizationBlock += $visualizations[$i] + "`n"

					# Add separator line between visualizations (but not after the last one)
					if ($i -lt $visualizations.Count - 1) {
						$visualizationBlock += ("-" * 80) + "`n`n"
					}
					else {
						$visualizationBlock += "`n"
					}
				}

				$visualizationBlock += "#>`n"

				# Update section headers in the Layout array
				$contentWithUpdatedSections = Update-LayoutSectionHeaders -Content $contentWithoutVisualization -Config $config

				# Combine visualization with content
				$newContent = $visualizationBlock + $contentWithUpdatedSections

				# Write back to file
				Set-Content -Path $file.FullName -Value $newContent -NoNewline
			}
		}
		catch {
			Write-Host -ForegroundColor Red "  => Error: $_"
		}
	}

	if ($Update) {
		Write-LogSuccess "Layout(s) updated successfully!" -NoLeadingNewline
	}
	else {
		Write-LogSuccess "Visualization complete!" -NoLeadingNewline
	}
}

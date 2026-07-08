function Add-WindowLayout {
	<#
	.SYNOPSIS
		Creates a window layout file for a workspace.
	.DESCRIPTION
		Creates a new layout .psd1 file in the Window/Layouts/{MachineType}/ directory.
		Generates a template with basic monitor and layout configuration that can be
		customized afterward.
	.PARAMETER WorkspaceName
		The workspace name for the layout.
	.PARAMETER MachineType
		The machine type(s) to create layouts for. Defaults to current machine type.
	.PARAMETER Simple
		If set, adds the workspace to SimpleLayoutWorkspaces in Configuration.psd1
		(layout-only, no window positioning).
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
	.PARAMETER LayoutsDirectory
		Override the Layouts directory path (for testing).
	.EXAMPLE
		Add-WindowLayout -WorkspaceName "MyWorkspace"
	.EXAMPLE
		Add-WindowLayout -WorkspaceName "MyWorkspace" -MachineType @("PC", "Laptop") -Simple
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$WorkspaceName,

		[string[]]$MachineType,

		[switch]$Simple,

		[string]$ConfigurationFilePath,
		[string]$LayoutsDirectory
	)

	$layoutsDir = if ($LayoutsDirectory) { $LayoutsDirectory } else { $script:LayoutsPath }
	if (-not $layoutsDir -or -not (Test-Path $layoutsDir)) {
		Write-LogError "Error: Layouts directory not found at '$layoutsDir'!"
		return
	}

	if (-not $MachineType) {
		if ($Configuration -and $Configuration.MachineType) {
			$MachineType = @($Configuration.MachineType)
		}
		else {
			$MachineType = @("Test")
		}
	}

	$template = @'
<#
LAYOUT VISUALIZATION
================================================================================
Workspace: LAYOUT_WORKSPACE_NAME (LAYOUT_MACHINE_TYPE)
================================================================================

VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One
+-------------------------+--------------------------+
|          Left           |          Right           |
|                         |                          |
+-------------------------+--------------------------+

#>
@{
	Monitors = @{
		Primary   = @{
			VirtualDesktopLayouts = @{
				1 = "One"
			}
		}
	}

	Layout   = @(
		# ==========================================================================
		# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One
		# ==========================================================================
		@{
			ProcessName   = $null
			WindowTitle   = $null
			DesktopNumber = 1
			Zone          = "Left"
			Monitor       = "Primary"
		}
	)
}
'@

	foreach ($machine in $MachineType) {
		$machineDir = Join-Path $layoutsDir $machine
		if (-not (Test-Path $machineDir)) {
			New-Item -Path $machineDir -ItemType Directory -Force | Out-Null
		}

		$fileName = "${WorkspaceName}_${machine}.psd1"
		$filePath = Join-Path $machineDir $fileName

		if (Test-Path $filePath) {
			Write-LogWarning "Layout file already exists: $fileName"
			continue
		}

		$content = $template.Replace('LAYOUT_WORKSPACE_NAME', $WorkspaceName).Replace('LAYOUT_MACHINE_TYPE', $machine)
		Set-Content -Path $filePath -Value $content
		Write-LogSuccess "Layout file created: $fileName"

		Write-LogDebug " [Add-WindowLayout] Created: $filePath"
	}

	# Optionally add to SimpleLayoutWorkspaces
	if ($Simple) {
		$configPath = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $script:ConfigurationPath }
		if (-not $configPath -or -not (Test-Path $configPath)) {
			Write-LogWarning "Warning: Configuration file not found, skipping SimpleLayoutWorkspaces update"
			return
		}

		$lines = @(Get-Content -Path $configPath)
		$section = Find-ConfigurationSection -Lines $lines -SectionName "SimpleLayoutWorkspaces"

		if ($section) {
			if ($section.StartIndex -eq $section.EndIndex) {
				# Single-line array: modify inline
				$line = $lines[$section.StartIndex]
				$closeIndex = $line.LastIndexOf(')')
				$lines[$section.StartIndex] = $line.Insert($closeIndex, ", `"$WorkspaceName`"")
			}
			else {
				# Multi-line array: insert before closing bracket
				$t = "`t"
				$newLines = [System.Collections.ArrayList]::new($lines)
				$newLines.Insert($section.EndIndex, "$($section.Indent)$t`"$WorkspaceName`"")
				$lines = @($newLines)
			}

			Set-Content -Path $configPath -Value $lines
			Write-LogSuccess "'$WorkspaceName' added to SimpleLayoutWorkspaces"
		}
	}
}

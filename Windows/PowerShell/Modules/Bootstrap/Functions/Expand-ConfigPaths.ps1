function Expand-ConfigPaths {
	<#
	.SYNOPSIS
		Expands placeholder tokens in configuration paths.

	.DESCRIPTION
		Replaces placeholder tokens ({Dev}, {User}, {MachineType}, {RepoRoot}, {AppData}) in configuration
		paths with their actual values based on machine type, base paths, and overrides.

		Token definitions:
		- {Dev}: Development directory for the machine type (e.g., C:\\dev on PC)
		- {User}: User-specific directory (e.g., C:\\Users\\You)
		- {MachineType}: The current machine type (PC, Laptop, Work, Test)
		- {RepoRoot}: Root of the WinuX repository
		- {AppData}: User AppData directory

		Calls `Expand-Hashtable` to do the recursive expansion, then applies machine-specific overrides
		from `Configuration.MachineOverrides[MachineType]` if present.

	.PARAMETER Configuration
		The full Configuration.psd1 hashtable.

	.PARAMETER MachineType
		The machine type (PC, Laptop, Work, Test). Used to select base paths and overrides.
		Falls back to "Test" if the machine type is not found in BasePaths.

	.EXAMPLE
		$paths = Expand-ConfigPaths -Configuration $Configuration -MachineType "PC"
		Expands all placeholder paths for the PC machine type.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Configuration,

		[Parameter(Mandatory = $true)]
		[string]$MachineType,

		# Explicit repository root for {RepoRoot}. Load-PathConfiguration passes the real,
		# self-located repo path so {RepoRoot} is independent of the clone folder name. The legacy
		# derive-from-config fallback in Expand-Hashtable no longer resolves (Projects.Self.Root is
		# itself "{RepoRoot}" now), so this parameter is effectively required for {RepoRoot} paths.
		[Parameter(Mandatory = $false)]
		[string]$RepoRoot = $null
	)

	if (-not $Configuration.BasePaths.ContainsKey($MachineType)) {
		Write-LogWarning "Machine type [$MachineType] not found in BasePaths. Using Test as fallback!"
		$MachineType = "Test"
	}

	$basePath = $Configuration.BasePaths[$MachineType].Dev
	$userPath = $Configuration.BasePaths[$MachineType].User

	$expandedPaths = Expand-Hashtable -Source $Configuration.PathTemplates -DevPath $basePath -UserPath $userPath -MachineTypeName $MachineType -RepoRoot $RepoRoot

	if ($Configuration.MachineOverrides.ContainsKey($MachineType)) {
		$overrides = $Configuration.MachineOverrides[$MachineType]
		if ($overrides.Count -gt 0) {
			Merge-Hashtable -Target $expandedPaths -Overrides $overrides
		}
	}

	return $expandedPaths
}

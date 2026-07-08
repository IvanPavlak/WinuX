function Update-Win11DebloatVendor {
	<#
	.SYNOPSIS
		Updates the vendored Win11Debloat files in this repository.

	.DESCRIPTION
		Runs the repository-local updater script at
		`Windows\Win11Debloat\Update-Win11DebloatVendor.ps1` so it can be
		invoked directly from the terminal as a module function.

	.PARAMETER ReleaseTag
		Release tag to vendor (example: 2026.05.11). Use `latest` (default)
		to fetch the newest GitHub release.

	.PARAMETER Repository
		GitHub repository in `owner/name` format.

	.EXAMPLE
		Update-Win11DebloatVendor
		Vendors the latest Win11Debloat release.

	.EXAMPLE
		Update-Win11DebloatVendor -ReleaseTag "2026.05.11"
		Vendors a specific Win11Debloat release tag.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$ReleaseTag = "latest",

		[Parameter()]
		[string]$Repository = "Raphire/Win11Debloat"
	)

	$repoRoot = $global:MachineSpecificPaths.Projects.Self.Root
	if (-not $repoRoot) {
		$repoRoot = $PSScriptRoot
		for ($i = 0; $i -lt 5; $i++) {
			$repoRoot = Split-Path -Path $repoRoot -Parent
		}
	}

	$updaterScriptPath = Join-Path $repoRoot "Windows\Win11Debloat\Update-Win11DebloatVendor.ps1"
	if (-not (Test-Path -Path $updaterScriptPath)) {
		Write-LogError "Error: updater script not found at [$updaterScriptPath]"
		return
	}

	& $updaterScriptPath @PSBoundParameters
}

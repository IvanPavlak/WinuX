function Get-PinnedApps {
	<#
	.SYNOPSIS
		Returns the version-pinned apps of one app list, machine-local overlay included.

	.DESCRIPTION
		Reads an app list through `Import-AppCsv` - so the machine-local `<name>.local.csv` is layered
		over the committed one - and returns the `App` of every row whose `Version` is a real version
		rather than the "track the latest" value. Used to identify apps that must NOT be upgraded
		because they are locked to a specific version.

		Reading through `Import-AppCsv` rather than the committed CSV directly is what makes the pin
		honour the overlay, and it matters in both directions: a version pinned only in the overlay is
		invisible in the base file, so a direct reader would let `Upgrade-All` upgrade straight past
		the pin - exactly the outcome pinning exists to prevent - and an app the overlay removed would
		still be reported as pinned and handed to `winget pin add`.

	.PARAMETER DataFileKey
		Which list to read: `WinGetApps`, `ScoopApps` or `ChocolateyApps`. Resolved through
		`BootstrapConfig.DataFiles`, the same way the installers resolve it.

	.PARAMETER VersionExcludeValue
		The `Version` value that means "not pinned". Defaults to "Latest" (WinGet); Scoop writes
		"latest", and Chocolatey leaves the cell empty, so its caller passes `$null` and every row
		carrying any version counts as pinned.

	.EXAMPLE
		Get-PinnedApps -DataFileKey WinGetApps
		Returns every app in the effective WinGet list with a Version other than "Latest".

	.EXAMPLE
		Get-PinnedApps -DataFileKey ScoopApps -VersionExcludeValue "latest"
		The same for Scoop, whose lists spell the value in lower case.
	#>
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('WinGetApps', 'ScoopApps', 'ChocolateyApps')]
		[string]$DataFileKey,

		[string]$VersionExcludeValue = "Latest"
	)

	# Import-AppCsv already drops comment and blank rows, but the filter is kept here as well: a
	# '#'-comment line that contains commas parses into a bogus row with a non-"Latest" Version, and
	# that garbage is what was once fed to `winget pin add` and hung the unattended upgrade on a fresh
	# machine. It costs nothing and the incident it guards against was silent.
	$apps = @(Import-AppCsv -DataFileKey $DataFileKey | Where-Object {
			-not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#')
		})

	if ($VersionExcludeValue) {
		return $apps | Where-Object { $_.Version -and $_.Version -ne $VersionExcludeValue } | Select-Object -ExpandProperty App
	}
 else {
		return $apps | Where-Object { $_.Version } | Select-Object -ExpandProperty App
	}
}

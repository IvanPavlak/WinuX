function Get-PinnedApps {
	<#
	.SYNOPSIS
		Reads version-pinned apps from a CSV file and returns the app names.

	.DESCRIPTION
		Imports a CSV file (e.g. WinGetApps.csv, ScoopApps.csv) and filters for entries
		that have a Version field matching the criteria. Used to identify apps that
		should NOT be upgraded because they are locked to a specific version.

	.PARAMETER CsvFileName
		Relative path to the CSV file (e.g. "Windows/bootstrap/WinGetApps.csv").
		Resolved relative to `MachineSpecificPaths.Projects.Self.Root`.

	.PARAMETER VersionExcludeValue
		Version value to exclude from the pinned results. Defaults to "Latest".
		Apps with this version value are not considered pinned.

	.EXAMPLE
		Get-PinnedApps -CsvFileName "Windows/bootstrap/WinGetApps.csv"
		Returns all apps in the CSV with a Version other than "Latest".

	.EXAMPLE
		Get-PinnedApps -CsvFileName "Windows/bootstrap/ScoopApps.csv" -VersionExcludeValue "latest"
		Returns all Scoop apps with a version other than "latest".
	#>
	param (
		[string]$CsvFileName,
		[string]$VersionExcludeValue = "Latest"
	)

	$csvPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath $CsvFileName

	# Skip the CSV's documentation-header comments (rows whose App starts with '#') and blank rows.
	# Import-Csv otherwise parses a comment line that happens to contain commas into a bogus row with a
	# non-"Latest" Version field, which would be reported as "pinned" and fed to `winget pin add` -
	# hanging the unattended upgrade on winget's first-run prompt. Same filter the install functions use.
	$apps = Import-Csv $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#') }

	if ($VersionExcludeValue) {
		return $apps | Where-Object { $_.Version -and $_.Version -ne $VersionExcludeValue } | Select-Object -ExpandProperty App
	}
 else {
		return $apps | Where-Object { $_.Version } | Select-Object -ExpandProperty App
	}
}

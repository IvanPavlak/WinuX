function Get-FancyZonesLayoutsPath {
	<#
	.SYNOPSIS
		Resolves the repository path of a FancyZones configuration file.

	.DESCRIPTION
		Returns the full path of a FancyZones configuration file inside the repository
		(Windows\FancyZones). The repository root is resolved through Get-RepositoryPath,
		which anchors on Configuration.psd1 instead of counting parent folders, so callers
		are immune to being relocated to a different depth.

		This is the single place that knows where the FancyZones files live in the repo.
		Consumers that need the file FancyZones actually loaded (e.g. the uuid idempotency
		check in Apply-FancyZones) should keep reading the %LOCALAPPDATA% copy instead -
		the repo file is the symlink TARGET, and zone math should always be computed from
		the repository's source of truth.

	.PARAMETER File
		Which FancyZones configuration file to resolve:
		- CustomLayouts (default) => Windows\FancyZones\custom-layouts.json
		- LayoutHotkeys           => Windows\FancyZones\layout-hotkeys.json

	.EXAMPLE
		$layoutsPath = Get-FancyZonesLayoutsPath
		Returns ...\Windows\FancyZones\custom-layouts.json for this repository.

	.EXAMPLE
		$hotkeysPath = Get-FancyZonesLayoutsPath -File LayoutHotkeys
		Returns ...\Windows\FancyZones\layout-hotkeys.json for this repository.

	.OUTPUTS
		[string] Full path to the requested file. The file is not required to exist -
		callers decide how to handle a missing file.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateSet('CustomLayouts', 'LayoutHotkeys')]
		[string]$File = 'CustomLayouts'
	)

	$fileNames = @{
		CustomLayouts = 'custom-layouts.json'
		LayoutHotkeys = 'layout-hotkeys.json'
	}

	$repoRoot = (Get-RepositoryPath -StartPath $PSScriptRoot).Repo
	return Join-Path -Path $repoRoot -ChildPath (Join-Path -Path 'Windows\FancyZones' -ChildPath $fileNames[$File])
}

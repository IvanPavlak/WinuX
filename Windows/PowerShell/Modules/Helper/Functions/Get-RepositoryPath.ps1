function Get-RepositoryPath {
	<#
	.SYNOPSIS
		Resolves the WinuX repository's key directories without hardcoding folder depth.

	.DESCRIPTION
		Every script in this repo lives at some depth beneath the repository root, and many need to
		reference sibling locations - the custom Modules root, the base Configuration.psd1, or the
		repository root itself. Historically each call site counted parent folders by hand (nested
		Split-Path calls or "..\..\.." literals). That count is a magic number: it silently resolves
		to the wrong place the moment a file is moved to a different depth.

		Get-RepositoryPath removes the guesswork. It walks upward from a starting directory until it
		finds the folder that holds Configuration.psd1 (always ...\Windows\PowerShell) and derives
		every root from that landmark. Because the search is anchored on a real file rather than on a
		level count, call sites are immune to being relocated to a different depth.

		By default the walk starts from this function's own on-disk location, so any caller that lives
		inside the repository can invoke it with no arguments and still resolve the repository it was
		loaded from. A caller whose location differs from the repository of interest - for example a
		function dot-sourced into a test sandbox - passes -StartPath to anchor the search on itself.

		The returned object exposes:
		- PowerShell : the folder that holds Configuration.psd1 (...\Windows\PowerShell)
		- Modules    : the custom module root                   (...\Windows\PowerShell\Modules)
		- Repo       : the repository root, two levels above PowerShell (...\Windows -> repo root)

	.PARAMETER StartPath
		Directory to begin the upward search from. Defaults to the folder containing this function
		(its module's Functions directory), which resolves the repository this module was loaded from.

	.EXAMPLE
		(Get-RepositoryPath).Modules
		Returns ...\Windows\PowerShell\Modules for the repository this function was loaded from.

	.EXAMPLE
		$paths = Get-RepositoryPath -StartPath $PSScriptRoot
		$config = Join-Path -Path $paths.PowerShell -ChildPath "Configuration.psd1"
		Resolves paths relative to the CALLER's location rather than this function's location.
	#>
	[CmdletBinding()]
	param(
		[string]$StartPath = $PSScriptRoot
	)

	# Walk up until we reach the directory that actually holds Configuration.psd1. This is the single
	# authoritative definition of "where the repo's PowerShell root is" - every other path derives
	# from it, so no other file in the repo needs to know how deep it sits.
	$dir = $StartPath
	while ($dir -and -not (Test-Path -LiteralPath (Join-Path -Path $dir -ChildPath "Configuration.psd1"))) {
		$dir = Split-Path -Path $dir -Parent
	}

	if (-not $dir) {
		throw "Get-RepositoryPath: could not locate Configuration.psd1 in any parent of '$StartPath'."
	}

	return [pscustomobject]@{
		PowerShell = $dir
		Modules    = Join-Path -Path $dir -ChildPath "Modules"
		Repo       = Split-Path -Path (Split-Path -Path $dir -Parent) -Parent
	}
}

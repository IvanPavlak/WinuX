function Get-ChangelogReleases {
	<#
	.SYNOPSIS
		Parses CHANGELOG.md into its [Unreleased] section and its released versions, newest first.

	.DESCRIPTION
		Reads the Keep-a-Changelog layout the repository uses: a "## [Unreleased]" heading, then one
		"## [X.Y.Z] - date" heading per release, each holding "### Added", "### Changed",
		"### Deprecated", "### Withdrawn", "### Removed", "### Breaking", "### Fixed" or "### Security"
		subsections.
		The compare links at the bottom of the file are not part of any section.

		Each release carries its version as text and as Major / Minor / Patch numbers (a SemVer
		pre-release suffix such as -rc.1 is kept in Version and ignored in the numbers) and a
		hashtable of its subsections, keyed by heading name ("Added", "Removed", ...), holding the
		subsection's text. Used by the contract gate (Test-ChangelogVersionBumps,
		Test-ContractCompatibility) and by Run-Tests -UpdateContractBaseline.

	.PARAMETER Path
		The changelog file.

	.PARAMETER Text
		The changelog's text, instead of -Path; tests pass a fixture this way.

	.OUTPUTS
		[pscustomobject] with Unreleased (a hashtable of subsections) and Releases (an array of
		objects with Version, Major, Minor, Patch and Sections, newest first).
	#>
	[CmdletBinding(DefaultParameterSetName = 'Path')]
	param(
		[Parameter(Mandatory = $true, ParameterSetName = 'Path')]
		[string]$Path,

		[Parameter(Mandatory = $true, ParameterSetName = 'Text')]
		[AllowEmptyString()]
		[string]$Text
	)

	if ($PSCmdlet.ParameterSetName -eq 'Path') {
		$Text = [System.IO.File]::ReadAllText($Path)
	}

	$lines = $Text -split "`r?`n"
	$unreleased = @{}
	$releases = [System.Collections.Generic.List[object]]::new()
	$current = $null
	$subsection = $null
	$buffer = [System.Text.StringBuilder]::new()

	$flush = {
		if ($null -ne $current -and $subsection) {
			$current[$subsection] = $buffer.ToString()
		}
		[void]$buffer.Clear()
	}

	foreach ($line in $lines) {
		if ($line -match '^## \[Unreleased\]') {
			& $flush
			$current = $unreleased
			$subsection = $null
			continue
		}
		if ($line -match '^## \[(?<version>(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-[0-9A-Za-z.-]+)?)\]') {
			& $flush
			$sections = @{}
			$releases.Add([pscustomobject]@{
					Version  = $Matches.version
					Major    = [int]$Matches.major
					Minor    = [int]$Matches.minor
					Patch    = [int]$Matches.patch
					Sections = $sections
				})
			$current = $sections
			$subsection = $null
			continue
		}
		if ($line -match '^\[[^\]]+\]:\s') {
			# A compare link: the reference definitions close the last section.
			& $flush
			$current = $null
			$subsection = $null
			continue
		}
		if ($line -match '^### (?<name>\w+)') {
			& $flush
			$subsection = $Matches.name
			continue
		}
		if ($subsection) {
			[void]$buffer.AppendLine($line)
		}
	}
	& $flush

	return [pscustomobject]@{
		Unreleased = $unreleased
		Releases   = $releases.ToArray()
	}
}

function Test-ChangelogVersionBumps {
	<#
	.SYNOPSIS
		Lists every release from 1.0.0 on whose version bump does not match what its changelog
		section says it changed.

	.DESCRIPTION
		VERSIONING.md's bump table, checked release by release against the one before it (the
		0.x series is exempt; the policy applies from 1.0.0):

		- A section with "### Removed" or "### Breaking" must be a MAJOR bump.
		- A MAJOR bump must have one of them - a MAJOR that breaks nothing is the gratuitous major
		  the policy exists to prevent, and it would make every fork review a merge for nothing.
		- A section with "### Added", "### Changed", "### Deprecated" or "### Withdrawn" must be at
		  least a MINOR bump; a PATCH carries only "### Fixed" and "### Security". "### Withdrawn"
		  removes an item that was never meant to be shared engine code, so it does not make a
		  release a MAJOR.
		- A MAJOR resets MINOR and PATCH to 0, a MINOR resets PATCH to 0, and every version is
		  higher than the one before it.

	.PARAMETER Releases
		The released versions, newest first (Get-ChangelogReleases).

	.OUTPUTS
		[string[]] - the violations; empty when every bump matches.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[object[]]$Releases
	)

	$violations = [System.Collections.Generic.List[string]]::new()

	for ($i = 0; $i -lt $Releases.Count - 1; $i++) {
		$new = $Releases[$i]
		$old = $Releases[$i + 1]
		if ($old.Major -lt 1) { continue }

		$sections = @($new.Sections.Keys)
		$breaks = ($sections -contains 'Removed') -or ($sections -contains 'Breaking')
		$adds = ($sections -contains 'Added') -or ($sections -contains 'Changed') -or ($sections -contains 'Deprecated') -or ($sections -contains 'Withdrawn')

		$major = $new.Major -gt $old.Major
		$minor = -not $major -and $new.Major -eq $old.Major -and $new.Minor -gt $old.Minor
		$patch = $new.Major -eq $old.Major -and $new.Minor -eq $old.Minor -and $new.Patch -gt $old.Patch

		if (-not ($major -or $minor -or $patch)) {
			$violations.Add("[$($new.Version)] is not higher than the release before it, [$($old.Version)].")
			continue
		}
		if ($breaks -and -not $major) {
			$violations.Add("[$($new.Version)] removes or breaks part of the contract (### Removed or ### Breaking), so it must be a MAJOR release, not a bump from [$($old.Version)].")
		}
		if ($major -and -not $breaks) {
			$violations.Add("[$($new.Version)] is a MAJOR release but removes and breaks nothing (no ### Removed or ### Breaking); release it as a MINOR or PATCH.")
		}
		if ($adds -and $patch) {
			$violations.Add("[$($new.Version)] adds, changes, deprecates or withdraws something (### Added, ### Changed, ### Deprecated or ### Withdrawn), so it must be at least a MINOR release; a PATCH carries only ### Fixed and ### Security.")
		}
		if ($major -and ($new.Minor -ne 0 -or $new.Patch -ne 0)) {
			$violations.Add("[$($new.Version)] is a MAJOR release, so its MINOR and PATCH must be 0.")
		}
		if ($minor -and $new.Patch -ne 0) {
			$violations.Add("[$($new.Version)] is a MINOR release, so its PATCH must be 0.")
		}
	}

	return [string[]]$violations.ToArray()
}

function Get-AiSkillManifest {
	<#
	.SYNOPSIS
		Reads the UPSTREAM.md manifest that Update-AiSkills writes into a vendored skills source folder.

	.DESCRIPTION
		Returns a hashtable with the pinned upstream commit and the names of every skill the
		manifest lists (the first column of its skill table, rows shaped like "| `name` | ...").
		Update-AiSkills uses the names to know which folders it owns and may replace or remove;
		anything else in the source folder is left alone. -Check uses the commit to compare
		against the current upstream head.

		A missing manifest yields an empty commit and no skills, which is how a source folder
		looks before its first vendoring.

	.PARAMETER Path
		The UPSTREAM.md to read.

	.EXAMPLE
		(Get-AiSkillManifest -Path "C:\Repo\AI\Skills\mattpocock\UPSTREAM.md").Skills
		Returns the vendored skill names.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path
	)

	$manifest = @{
		Commit = ""
		Skills = @()
	}

	if (-not (Test-Path -Path $Path)) {
		return $manifest
	}

	$skills = @()
	foreach ($line in Get-Content -Path $Path) {
		if ($line -match '^\|\s*`([^`]+)`\s*\|') {
			$skills += $Matches[1]
		}
		elseif (-not $manifest.Commit -and $line -match '^\-\s+\*\*Commit:\*\*\s+`([0-9a-fA-F]+)`') {
			$manifest.Commit = $Matches[1]
		}
	}

	$manifest.Skills = $skills
	return $manifest
}

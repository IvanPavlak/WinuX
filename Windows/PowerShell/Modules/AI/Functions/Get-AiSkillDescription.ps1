function Get-AiSkillDescription {
	<#
	.SYNOPSIS
		Extracts the description from a SKILL.md YAML frontmatter as one line of Markdown table text.

	.DESCRIPTION
		Agent Skills declare a `description:` in the YAML frontmatter at the top of SKILL.md.
		This returns it flattened to a single line for the UPSTREAM.md skill table that
		Update-AiSkills writes: single-line values, quoted values (with escaped quotes
		unescaped), and the folded or literal block forms ("description: >" or "|" followed by
		indented lines) are all handled, and pipes are escaped so the table stays intact.
		Returns an empty string when the file has no frontmatter or no description.

	.PARAMETER SkillFile
		The SKILL.md to read.

	.EXAMPLE
		Get-AiSkillDescription -SkillFile "C:\Repo\AI\Skills\mattpocock\grill-me\SKILL.md"
		Returns e.g. "A relentless interview to sharpen a plan or design."
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$SkillFile
	)

	$lines = @(Get-Content -Path $SkillFile)
	if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
		return ""
	}

	$description = $null
	for ($i = 1; $i -lt $lines.Count; $i++) {
		$line = $lines[$i]
		if ($line.Trim() -eq '---') { break }

		if ($null -eq $description) {
			if ($line -match '^description:\s*(.*)$') {
				$value = $Matches[1].Trim()
				$description = if ($value -in @('', '>', '|', '>-', '|-')) { "" } else { $value }
			}
			continue
		}

		# Inside a block scalar: indented lines continue the description, anything else ends it.
		if ($line -match '^\s+\S') {
			$description = ($description + " " + $line.Trim()).Trim()
		}
		else {
			break
		}
	}

	if ($null -eq $description) {
		return ""
	}

	$description = $description.Trim()
	if ($description.Length -ge 2 -and (($description[0] -eq '"' -and $description[-1] -eq '"') -or ($description[0] -eq "'" -and $description[-1] -eq "'"))) {
		$description = $description.Substring(1, $description.Length - 2) -replace '\\"', '"'
	}

	return ($description -replace '\|', '\|')
}

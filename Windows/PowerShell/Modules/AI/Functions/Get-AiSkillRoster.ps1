function Get-AiSkillRoster {
	<#
	.SYNOPSIS
		Enumerates every Agent Skill under the skills root, flattened by skill name.

	.DESCRIPTION
		Every harness discovers user-level skills from one flat directory of <skill>/SKILL.md,
		so the repository's <Root>\<source>\<skill>\SKILL.md tree has to be flattened before it
		can be linked or listed - and both readings have to flatten it the same way, or
		List-Skills would report a roster Deploy-AiSkills does not deploy. This is that single
		reading: sources are walked in name order, a folder without a SKILL.md is not a skill,
		and when two sources carry the same skill name the first source alphabetically wins.

		Returns:

		  Root        The skills root the roster was read from.
		  Skills      An ordered map of skill name -> @{ Name; Path; Source }, in the order the
		              walk found them (source name, then skill name).
		  Duplicates  One entry per losing name -> @{ Name; Source; KeptFrom }, so a caller can
		              report the collision in its own voice rather than this function writing
		              to the log for everybody.

		A missing root is not an error: it yields an empty roster, which is how a vanilla
		install looks before any source is configured.

	.PARAMETER Root
		The skills root to walk. Defaults to (Resolve-AiSkillsConfig).Root.

	.EXAMPLE
		(Get-AiSkillRoster).Skills.Count
		Returns how many distinct skills the repository carries.

	.EXAMPLE
		(Get-AiSkillRoster -Root "C:\Repo\AI\Skills").Skills['teach-me'].Source
		Returns e.g. "own".
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$Root
	)

	if (-not $Root) {
		$Root = (Resolve-AiSkillsConfig).Root
	}

	$roster = @{
		Root       = $Root
		Skills     = [ordered]@{}
		Duplicates = @()
	}

	if (-not (Test-Path -Path $Root)) {
		return $roster
	}

	foreach ($sourceDir in (Get-ChildItem -Path $Root -Directory | Sort-Object Name)) {
		foreach ($skillDir in (Get-ChildItem -Path $sourceDir.FullName -Directory | Sort-Object Name)) {
			if (-not (Test-Path -Path (Join-Path $skillDir.FullName "SKILL.md"))) {
				continue
			}
			if ($roster.Skills.Contains($skillDir.Name)) {
				$roster.Duplicates += @{
					Name     = $skillDir.Name
					Source   = $sourceDir.Name
					KeptFrom = $roster.Skills[$skillDir.Name].Source
				}
				continue
			}
			$roster.Skills[$skillDir.Name] = @{
				Name   = $skillDir.Name
				Path   = $skillDir.FullName
				Source = $sourceDir.Name
			}
		}
	}

	return $roster
}

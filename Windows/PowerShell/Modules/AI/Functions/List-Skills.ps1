function List-Skills {
	<#
    .SYNOPSIS
        List the Agent Skills the repository carries, with optional filtering and a deployment check.

    .DESCRIPTION
        The catalog counterpart to Deploy-AiSkills: it answers "what skills does this machine
        have, and are they actually linked into the harnesses?" without deploying anything.

        The roster is read from disk (Get-AiSkillRoster over AiSkills.Root), not from the
        documentation. Skills are mostly vendored from upstream repositories, so disk is the
        only source that stays honest across a refresh - a docs-driven listing would show the
        handful of skills a fork happened to write a page for and miss everything Update-AiSkills
        brought in. Each skill's summary is its own SKILL.md frontmatter `description:`, which is
        maintained by whoever wrote the skill and is therefore true by construction.

        -ListDiscrepancies compares what the repository carries against what is actually linked
        into the Windows harness directories, which is the analogue of List-Functions comparing
        the documentation against the loaded session: declared against in effect. It reports a
        skill that is present but not linked (usually "added a skill, never re-ran
        Deploy-AiSkills"), a harness entry that shadows a skill with a real folder or a link
        pointing somewhere else, and a link into the skills root whose skill is gone. Links to
        anything else are ignored, exactly as Deploy-AiSkills leaves them alone. WSL harnesses
        are deliberately out of scope: reading them means shelling into the distribution, which
        is too slow for a listing - re-run Deploy-AiSkills to reconcile those.

        The catalog is rendered with the same two helpers List-Functions uses - a
        Create-CenteredBorder group header and Show-FunctionDetails per entry - so a skill reads
        exactly like a function entry: name, indented description, then indented "Key => value"
        rows in the ShowFunctionDetailsColors palette. Nothing here formats output itself, so the
        two catalogs cannot drift apart. Every line this function emits on its own account goes
        through the Logging module (Write-LogStep for the borders, Write-LogWarning per audit
        finding, Write-LogSuccess for the all-clear), so it is mirrored into the session log.

    .PARAMETER Source
        Filter to specific sources (the subfolders of the skills root, e.g. 'own'). Resolved by
        number or name; pass an empty value (-Source @()) to pick from the menu.

    .PARAMETER Skill
        Filter to specific skill names. Resolved the same way as -Source.

    .PARAMETER ListDiscrepancies
        Compare the skills on disk against the links in the Windows harness directories.

    .PARAMETER Quiet
        Suppress the success banner when -ListDiscrepancies finds nothing wrong.

    .EXAMPLE
        List-Skills
        Lists every skill, grouped by source.

    .EXAMPLE
        List-Skills -Source own
        Lists only the hand-written skills.

    .EXAMPLE
        List-Skills -ListDiscrepancies
        Reports skills that are not linked into a harness, and stale links that are.
    #>
	[CmdletBinding(DefaultParameterSetName = 'ListAll')]
	param (
		[Parameter(Mandatory = $false, ParameterSetName = 'BySource')]
		[string[]]$Source,

		[Parameter(Mandatory = $false, ParameterSetName = 'BySkill')]
		[string[]]$Skill,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$ListDiscrepancies,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$Quiet
	)

	$config = Resolve-AiSkillsConfig
	$roster = Get-AiSkillRoster -Root $config.Root

	if ($roster.Skills.Count -eq 0) {
		Write-LogWarning "No skills found under [$($config.Root)] - configure AiSkills.Sources and run Update-AiSkills, or add a skill under it!"
		return
	}

	# Group by source for display; the roster is already ordered by source then skill name.
	$bySource = [ordered]@{}
	foreach ($name in $roster.Skills.Keys) {
		$entry = $roster.Skills[$name]
		if (-not $bySource.Contains($entry.Source)) { $bySource[$entry.Source] = @() }
		$bySource[$entry.Source] += $entry
	}

	if ($PSCmdlet.ParameterSetName -eq 'DiscrepancyCheck') {
		# Findings are collected per harness and rendered after the walk, so the report opens with
		# its title only when there is something to report and -Quiet can stay silent otherwise.
		$findings = @()

		foreach ($harness in $config.Harnesses) {
			$notLinked = @()
			$shadowed = @()
			$stale = @()

			if (-not (Test-Path -Path $harness -PathType Container)) {
				$findings += @{
					Harness = $harness
					Items   = @(@{ Summary = "The harness directory does not exist, so no skill is linked into it:"; List = @($roster.Skills.Keys) })
				}
				continue
			}

			foreach ($name in $roster.Skills.Keys) {
				$linkPath = Join-Path $harness $name
				$item = Get-Item -Path $linkPath -Force -ErrorAction SilentlyContinue

				if (-not $item) {
					$notLinked += $name
					continue
				}
				if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
					$shadowed += "$name (a real item sits at that path)"
					continue
				}

				$target = [string]$item.LinkTarget
				if (-not $target) { $target = [string](@($item.Target)[0]) }
				if ($target.TrimEnd('\') -ne $roster.Skills[$name].Path.TrimEnd('\')) {
					$shadowed += "$name (links to [$target])"
				}
			}

			# Links into the skills root whose skill no longer exists, or whose name the roster
			# no longer carries. Links to anything else belong to other tools and are left alone.
			foreach ($child in Get-ChildItem -Path $harness -Force -ErrorAction SilentlyContinue) {
				if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
				$target = [string]$child.LinkTarget
				if (-not $target) { $target = [string](@($child.Target)[0]) }
				if (-not $target -or -not $target.StartsWith($roster.Root, [StringComparison]::OrdinalIgnoreCase)) { continue }
				if (-not (Test-Path -Path $target)) {
					$stale += "$($child.Name) (target is gone)"
				}
				elseif (-not $roster.Skills.Contains($child.Name)) {
					$stale += "$($child.Name) (no longer in the roster)"
				}
			}

			$items = @()
			if ($notLinked.Count -gt 0) {
				$items += @{ Summary = "In the repository but NOT linked into this harness:"; List = $notLinked }
			}
			if ($shadowed.Count -gt 0) {
				$items += @{ Summary = "Harness entr(y/ies) that do NOT point at the skill of that name:"; List = $shadowed }
			}
			if ($stale.Count -gt 0) {
				$items += @{ Summary = "Link(s) into the skills root that are stale:"; List = $stale }
			}
			if ($items.Count -gt 0) {
				$findings += @{ Harness = $harness; Items = $items }
			}
		}

		$duplicateLines = @($roster.Duplicates | ForEach-Object {
				"$($_.Name) is in [$($_.Source)] and [$($_.KeptFrom)] - the one from [$($_.KeptFrom)] is the one deployed"
			})

		if ($findings.Count -eq 0 -and $duplicateLines.Count -eq 0) {
			if (-not $Quiet) {
				Write-LogSuccess "All $($roster.Skills.Count) skill(s) are linked into every harness!"
			}
			return
		}

		Write-LogTitle "AI Skill Discrepancies"

		foreach ($finding in $findings) {
			Write-LogStep "[$($finding.Harness)]"
			foreach ($item in $finding.Items) {
				Write-LogWarning $item.Summary
				Write-LogList $item.List
			}
		}

		if ($duplicateLines.Count -gt 0) {
			Write-LogWarning "Duplicate skill name(s) across sources:"
			Write-LogList $duplicateLines
		}

		Write-LogWarning "Run Deploy-AiSkills to reconcile (it also covers the WSL harnesses, which this check does not read)."

		return
	}

	$selectedSources = $bySource.Keys

	if ($PSCmdlet.ParameterSetName -eq 'BySource') {
		$resolveParams = @{
			InputObject             = $Source
			OptionList              = @($bySource.Keys | Sort-Object)
			MenuTitle               = "[Available Sources]"
			PromptMessage           = "Enter source(s) to list by number or name"
			AllowMultipleSelections = $true
		}
		$selectedSources = Resolve-Selection @resolveParams
		if (-not $selectedSources) { return }
	}

	$selectedSkills = $null
	if ($PSCmdlet.ParameterSetName -eq 'BySkill') {
		$resolveParams = @{
			InputObject             = $Skill
			OptionList              = @($roster.Skills.Keys | Sort-Object)
			MenuTitle               = "[Available Skills]"
			PromptMessage           = "Enter skill(s) to view by number or name"
			AllowMultipleSelections = $true
		}
		$selectedSkills = Resolve-Selection @resolveParams
		if (-not $selectedSkills) { return }
	}

	# Rendered exactly like List-Functions: a centered border per group, then the shared
	# man-style renderer per entry. Show-FunctionDetails takes a name and an ordered map of
	# fields, so a skill's frontmatter description and its folder render in the same shape,
	# indentation and palette as a function's Description and Parameters bullets - one catalog
	# look for both commands, and no second copy of the formatting to keep in step.
	$shown = 0
	foreach ($sourceName in $selectedSources) {
		$entries = @($bySource[$sourceName])
		if ($selectedSkills) {
			$entries = @($entries | Where-Object { $selectedSkills -contains $_.Name })
		}
		if ($entries.Count -eq 0) { continue }

		Write-LogStep (Create-CenteredBorder -Title $sourceName) -Style Title -BlankLineAfter

		foreach ($entry in $entries) {
			# Get-AiSkillDescription escapes pipes for the UPSTREAM.md table; undo that for display.
			$description = (Get-AiSkillDescription -SkillFile (Join-Path $entry.Path "SKILL.md")) -replace '\\\|', '|'

			$info = [ordered]@{}
			if ($description) { $info['Description'] = $description }
			$info['Location'] = $entry.Path

			Show-FunctionDetails -FunctionName $entry.Name -FunctionInfo $info
			$shown++
		}
	}

	if ($shown -eq 0) {
		Write-LogWarning "No skill matched the filter!"
		return
	}

	Write-LogStep (Create-CenteredBorder -Title "Total skill count => $shown") -Style Title -BlankLineAfter
}

function List-AiArtifacts {
	<#
	.SYNOPSIS
		List the AI skills, mods, rules, prompts and agents the repository carries, with filters and a deployment check.

	.DESCRIPTION
		The catalog counterpart to Deploy-AiArtifacts: it answers "what artifacts does this
		machine have, and are they actually deployed into the apps?" without deploying anything.

		The roster is read from disk the way Deploy-AiArtifacts reads it (Get-AiArtifactRoster
		per kind: own first, then winux, example and the vendored sources in name order, the
		first winning an item name two carry, minus AiArtifacts.Exclude), not from the
		documentation, so a vendored refresh shows up at once. Each item's summary is the
		`description:` of its frontmatter (SKILL.md, or the first Markdown file of a rules,
		prompt or agent item) or the description of a mod's plugin.json.

		Output is grouped by kind, then by source, and rendered with the same two helpers
		List-Functions uses (Create-CenteredBorder and Show-FunctionDetails), so an artifact
		reads like a function entry.

		-ListDiscrepancies compares the roster with what is deployed into the Windows
		destinations of the harnesses AiArtifacts.Deploy names (Get-AiArtifactPlan): an item that
		is not linked (or copied), an entry that shadows one with a real file or points
		elsewhere, a dangling link into the artifacts root, and an item name two sources carry.
		WSL twins are out of scope - reading them means shelling into the distribution, which is
		too slow for a listing; re-run Deploy-AiArtifacts to reconcile those.

	.PARAMETER Kind
		Limit the listing (or the check) to these kinds: Skills, Mods, Rules, Prompts, Agents.

	.PARAMETER Source
		Filter to specific sources (own, winux, a vendored source). Resolved by number or name;
		pass an empty value (-Source @()) to pick from the menu.

	.PARAMETER Name
		Filter item names; wildcards allowed, case-insensitive. Pass an empty value (-Name @())
		to pick from the menu.

	.PARAMETER ListDiscrepancies
		Compare the roster against what is deployed into the Windows destinations.

	.PARAMETER Quiet
		Suppress the success banner when -ListDiscrepancies finds nothing wrong.

	.EXAMPLE
		List-AiArtifacts
		Lists every artifact, grouped by kind and source.

	.EXAMPLE
		List-AiArtifacts -Kind Skills -Source own
		Lists only your own skills.

	.EXAMPLE
		List-AiArtifacts -ListDiscrepancies
		Reports artifacts that are not deployed into a harness, and stale links that are.
	#>
	[CmdletBinding(DefaultParameterSetName = 'List')]
	param(
		[Parameter(Position = 0)]
		[ValidateSet('Skills', 'Mods', 'Rules', 'Prompts', 'Agents')]
		[string[]]$Kind,

		[Parameter(ParameterSetName = 'List')]
		[AllowEmptyCollection()]
		[string[]]$Source,

		[Parameter(ParameterSetName = 'List')]
		[AllowEmptyCollection()]
		[string[]]$Name,

		[Parameter(Mandatory = $true, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$ListDiscrepancies,

		[Parameter(ParameterSetName = 'DiscrepancyCheck')]
		[switch]$Quiet
	)

	$config = Resolve-AiArtifactsConfig
	$kinds = if ($Kind) { @($Kind | ForEach-Object { $_.ToLowerInvariant() }) } else { @('skills', 'mods', 'rules', 'prompts', 'agents') }

	$rosters = [ordered]@{}
	foreach ($kindName in $kinds) {
		$rosters[$kindName] = Get-AiArtifactRoster -Kind $kindName -Config $config
	}

	$total = 0
	foreach ($roster in $rosters.Values) { $total += $roster.Items.Count }
	if ($total -eq 0) {
		Write-LogWarning "No AI artifacts found under [$($config.Root)] - configure AiArtifacts.Sources and run Update-AiArtifacts, or add items under it!"
		return
	}

	if ($PSCmdlet.ParameterSetName -eq 'DiscrepancyCheck') {
		$planParams = @{ Config = $config }
		if ($Kind) { $planParams.Kind = $Kind }
		$plan = Get-AiArtifactPlan @planParams

		# Findings are collected per destination and rendered after the walk, so the report opens
		# with its title only when there is something to report and -Quiet can stay silent.
		$findings = @()
		$root = $config.Root.TrimEnd('\')
		foreach ($destination in $plan.Destinations) {
			$notDeployed = @()
			$shadowed = @()
			$stale = @()
			$expected = @{}

			foreach ($item in $destination.Items) {
				$expected[(Split-Path -Path $item.Target -Leaf).ToLowerInvariant()] = $true
				$current = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
				if (-not $current) {
					$notDeployed += $item.Name
					continue
				}
				$isLink = $current.Attributes -band [IO.FileAttributes]::ReparsePoint
				if ($destination.Placement -eq 'copy') {
					if ($isLink) { $shadowed += "$($item.Name) (a link sits where a copy goes)" }
					continue
				}
				if (-not $isLink) {
					$shadowed += "$($item.Name) (a real item sits at [$($item.Target)])"
					continue
				}
				$target = [string]$current.LinkTarget
				if (-not $target) { $target = [string](@($current.Target)[0]) }
				if ($target.TrimEnd('\') -ne $item.Source.TrimEnd('\')) {
					$shadowed += "$($item.Name) (links to [$target])"
				}
			}

			if ($destination.Placement -ne 'file' -and (Test-Path -LiteralPath $destination.Path -PathType Container)) {
				foreach ($child in Get-ChildItem -LiteralPath $destination.Path -Force -ErrorAction SilentlyContinue) {
					if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
					$target = [string]$child.LinkTarget
					if (-not $target) { $target = [string](@($child.Target)[0]) }
					if (-not $target -or -not $target.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) { continue }
					if (-not (Test-Path -LiteralPath $target)) {
						$stale += "$($child.Name) (target is gone)"
					}
					elseif (-not $expected.ContainsKey($child.Name.ToLowerInvariant())) {
						$stale += "$($child.Name) (no longer in the roster)"
					}
				}
			}

			$items = @()
			if ($notDeployed.Count -gt 0) { $items += @{ Summary = "In the repository but NOT deployed here:"; List = $notDeployed } }
			if ($shadowed.Count -gt 0) { $items += @{ Summary = "Entr(y/ies) that do NOT point at the artifact of that name:"; List = $shadowed } }
			if ($stale.Count -gt 0) { $items += @{ Summary = "Link(s) into the artifacts root that are stale:"; List = $stale } }
			if ($items.Count -gt 0) {
				$findings += @{ Destination = "[$($destination.Harness)] $($destination.Kind) => $($destination.Path)"; Items = $items }
			}
		}

		$duplicateLines = @()
		foreach ($roster in $rosters.Values) {
			foreach ($duplicate in $roster.Duplicates) {
				$duplicateLines += "$($roster.Kind)/$($duplicate.Name) is in [$($duplicate.Source)] and [$($duplicate.KeptFrom)] - the one from [$($duplicate.KeptFrom)] is the one deployed"
			}
		}

		if ($findings.Count -eq 0 -and $duplicateLines.Count -eq 0 -and $plan.Warnings.Count -eq 0) {
			if (-not $Quiet) {
				Write-LogSuccess "All AI artifacts are deployed into every destination of [$($config.Deploy -join ', ')]!"
			}
			return
		}

		Write-LogTitle "AI Artifact Discrepancies"

		foreach ($message in $plan.Warnings) { Write-LogWarning $message }

		foreach ($finding in $findings) {
			Write-LogStep $finding.Destination
			foreach ($item in $finding.Items) {
				Write-LogWarning $item.Summary
				Write-LogList $item.List
			}
		}

		if ($duplicateLines.Count -gt 0) {
			Write-LogWarning "Duplicate item name(s) across sources:"
			Write-LogList $duplicateLines
		}

		Write-LogWarning "Run Deploy-AiArtifacts to reconcile (it also covers the WSL twins, which this check does not read)."
		return
	}

	$selectedSources = $null
	if ($PSBoundParameters.ContainsKey('Source')) {
		$allSources = @($rosters.Values | ForEach-Object { $_.Items.Values } | ForEach-Object { $_.Source } | Sort-Object -Unique)
		$resolveParams = @{
			InputObject             = $Source
			OptionList              = $allSources
			MenuTitle               = "[Available Sources]"
			PromptMessage           = "Enter source(s) to list by number or name"
			AllowMultipleSelections = $true
		}
		$selectedSources = @(Resolve-Selection @resolveParams)
		if ($selectedSources.Count -eq 0) { return }
	}

	$namePatterns = $null
	if ($PSBoundParameters.ContainsKey('Name')) {
		if (@($Name).Count -eq 0) {
			$allNames = @($rosters.Values | ForEach-Object { $_.Items.Keys } | Sort-Object -Unique)
			$resolveParams = @{
				InputObject             = $Name
				OptionList              = $allNames
				MenuTitle               = "[Available Artifacts]"
				PromptMessage           = "Enter artifact(s) to view by number or name"
				AllowMultipleSelections = $true
			}
			$namePatterns = @(Resolve-Selection @resolveParams)
			if ($namePatterns.Count -eq 0) { return }
		}
		else {
			$namePatterns = @($Name)
		}
	}

	# Rendered exactly like List-Functions: a centered border per group, then the shared
	# man-style renderer per entry.
	$shown = 0
	foreach ($kindName in $rosters.Keys) {
		$bySource = [ordered]@{}
		foreach ($item in $rosters[$kindName].Items.Values) {
			if ($selectedSources -and $selectedSources -notcontains $item.Source) { continue }
			if ($namePatterns -and -not @($namePatterns | Where-Object { $item.Name -like $_ }).Count) { continue }
			if (-not $bySource.Contains($item.Source)) { $bySource[$item.Source] = @() }
			$bySource[$item.Source] += $item
		}

		foreach ($sourceName in $bySource.Keys) {
			Write-LogStep (Create-CenteredBorder -Title "$kindName - $sourceName") -Style Title -BlankLineAfter

			foreach ($item in $bySource[$sourceName]) {
				$description = ""
				if ($kindName -eq 'mods') {
					try {
						$description = [string](Get-Content -LiteralPath (Join-Path $item.Path ".claude-plugin\plugin.json") -Raw | ConvertFrom-Json -ErrorAction Stop).description
					}
					catch {
						Write-LogDebug "Unreadable plugin.json of [$($item.Name)] => $($_.Exception.Message)"
					}
				}
				else {
					$file = if ($kindName -eq 'skills') { Get-Item -LiteralPath (Join-Path $item.Path "SKILL.md") } else { Get-ChildItem -LiteralPath $item.Path -File -Filter "*.md" | Sort-Object Name | Select-Object -First 1 }
					# Get-AiSkillDescription escapes pipes for the UPSTREAM.md table; undo that for display.
					if ($file) { $description = (Get-AiSkillDescription -SkillFile $file.FullName) -replace '\\\|', '|' }
				}

				$info = [ordered]@{}
				if ($description) { $info['Description'] = $description }
				$info['Location'] = $item.Path

				Show-FunctionDetails -FunctionName $item.Name -FunctionInfo $info
				$shown++
			}
		}
	}

	if ($shown -eq 0) {
		Write-LogWarning "No AI artifact matched the filter!"
		return
	}

	Write-LogStep (Create-CenteredBorder -Title "Total artifact count => $shown") -Style Title -BlankLineAfter
}

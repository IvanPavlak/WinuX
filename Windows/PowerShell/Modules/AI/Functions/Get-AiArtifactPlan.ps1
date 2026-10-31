function Get-AiArtifactPlan {
	<#
	.SYNOPSIS
		Builds the deployment plan of the AI artifacts: every destination of the harnesses this machine deploys into, with the items that go there.

	.DESCRIPTION
		Joins the harness definitions (AiHarnesses, filtered by AiArtifacts.Deploy for this
		machine type) with the roster of each kind (Get-AiArtifactRoster), so Deploy-AiArtifacts
		and List-AiArtifacts -ListDiscrepancies read one plan:

		  - A destination two harnesses name (Codex, Gemini CLI and Copilot all read
		    ~\.agents\skills) is planned once, for the first; a second definition that differs
		    in kind, placement or files is reported.
		  - Each and Copy destinations get one entry per item: the item folder itself when its
		    Files list holds ".", else the first file of the list the item has, named <item>
		    plus that file's extension (claude.md as <item>.md, copilot.agent.md as
		    <item>.agent.md). An item with none of them is left out of that destination.
		  - A File destination gets the item AiArtifacts.Use names for its kind, if it has one
		    of the destination's files; without a Use entry it links nothing. With an AI
		    profile active, the profile's Rules item is the rules Use entry.
		  - Repository-scoped skills (manifest rows scoped repo:<name>) get one destination per
		    repository when claude-code is deployed: <repository>\.claude\skills, harness
		    "repo:<name>", hook git-exclude (Deploy-AiArtifacts lists the links in that
		    repository's .git\info\exclude). The repository is found by name in
		    RepositoryGroups (Resolve-RepositoryTargets); an unknown one is a warning.

		Returns:

		  Destinations  One entry per destination, in harness then definition order:
		                @{ Harness; Kind; Placement; Hooks; Path; WSLPath; Items }, each item
		                @{ Kind; Name; Source; Target; WSLTarget } (Source is the item folder or
		                file, Target the Windows path, WSLTarget the WSL twin or empty).
		  Warnings      Problems of the configuration or the roster (an unknown harness, a
		                destination without Kind, Placement, Files or Path, a duplicate item
		                name, a Use entry naming no item).
		  Notes         Things left out on purpose (no Use entry, an item without the files a
		                File destination takes, a harness without destinations).

	.PARAMETER Kind
		Limits the plan to these kinds. Defaults to every kind.

	.PARAMETER Config
		A resolved configuration (Resolve-AiArtifactsConfig). Defaults to resolving the global one.

	.EXAMPLE
		(Get-AiArtifactPlan).Destinations | ForEach-Object { "$($_.Path): $($_.Items.Count)" }
		Lists every destination and how many items go there.

	.EXAMPLE
		Get-AiArtifactPlan -Kind Rules
		Returns only the rules destinations (CLAUDE.md, AGENTS.md, the managed settings, ...).
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[ValidateSet('Skills', 'Mods', 'Rules', 'Prompts', 'Agents')]
		[string[]]$Kind,

		[Parameter()]
		[hashtable]$Config
	)

	if (-not $Config) {
		$Config = Resolve-AiArtifactsConfig
	}

	$kinds = @('skills', 'mods', 'rules', 'prompts', 'agents')
	$wanted = if ($Kind) { @($Kind | ForEach-Object { $_.ToLowerInvariant() }) } else { $kinds }

	$plan = @{
		Destinations = @()
		Warnings     = @()
		Notes        = @()
	}

	foreach ($name in $Config.Unknown) {
		$plan.Warnings += "Harness [$name] of AiArtifacts.Deploy has no AiHarnesses entry - skipped"
	}

	# Destinations, deduplicated by path (case-insensitive, as Windows paths are).
	$planned = @{}
	$selected = @()
	foreach ($harness in $Config.Harnesses.Values) {
		if (@($harness.Destinations).Count -eq 0) {
			$plan.Notes += "Harness [$($harness.Name)] has no destination for this machine type"
			continue
		}
		foreach ($destination in $harness.Destinations) {
			if ($kinds -notcontains $destination.Kind -or @('each', 'copy', 'file') -notcontains $destination.Placement -or @($destination.Files).Count -eq 0 -or -not $destination.Path) {
				$plan.Warnings += "Harness [$($harness.Name)]: a destination needs Kind (Skills, Mods, Rules, Prompts, Agents), Placement (Each, Copy, File), Files and Path => [$($destination.Kind) $($destination.Placement) $($destination.Path)]"
				continue
			}
			if ($wanted -notcontains $destination.Kind) { continue }
			$signature = "$($destination.Kind)|$($destination.Placement)|$(@($destination.Files) -join ',')"
			$pathKey = $destination.Path.TrimEnd('\').ToLowerInvariant()
			if ($planned.ContainsKey($pathKey)) {
				if ($planned[$pathKey] -ne $signature) {
					$plan.Warnings += "Harness [$($harness.Name)] names [$($destination.Path)] differently from an earlier harness - the first definition is kept"
				}
				continue
			}
			$planned[$pathKey] = $signature
			$selected += @{ Harness = $harness.Name; Destination = $destination }
		}
	}

	$rosters = @{}
	foreach ($entry in $selected) {
		$destination = $entry.Destination
		$kindName = $destination.Kind
		if (-not $rosters.ContainsKey($kindName)) {
			$roster = Get-AiArtifactRoster -Kind $kindName -Config $Config
			foreach ($duplicate in $roster.Duplicates) {
				$plan.Warnings += "Duplicate $($kindName.TrimEnd('s')) [$($duplicate.Name)] in source [$($duplicate.Source)] - keeping the one from [$($duplicate.KeptFrom)]"
			}
			foreach ($problem in @($roster.Problems)) { $plan.Warnings += $problem }
			$rosters[$kindName] = $roster.Items
		}
		$items = $rosters[$kindName]

		$planDestination = @{
			Harness   = $entry.Harness
			Kind      = $kindName
			Placement = $destination.Placement
			Hooks     = @($destination.Hooks)
			Path      = $destination.Path
			WSLPath   = $destination.WSLPath
			Items     = @()
		}

		if ($destination.Placement -eq 'file') {
			if (-not $Config.Use.ContainsKey($kindName)) {
				$plan.Notes += "[$($destination.Path)] has no AiArtifacts.Use.$((Get-Culture).TextInfo.ToTitleCase($kindName)) entry - nothing to link"
				$plan.Destinations += $planDestination
				continue
			}
			$used = $Config.Use[$kindName]
			$itemKey = @($items.Keys | Where-Object { $_ -eq $used }) | Select-Object -First 1
			if ($null -eq $itemKey) {
				$plan.Warnings += "AiArtifacts.Use.$((Get-Culture).TextInfo.ToTitleCase($kindName)) = [$used] names no $($kindName.TrimEnd('s')) item (excluded, or under no source read)"
				$plan.Destinations += $planDestination
				continue
			}
			$item = $items[$itemKey]
			$source = $null
			foreach ($file in $destination.Files) {
				if ($file -eq '.') { $source = $item.Path; break }
				$candidate = Join-Path $item.Path $file
				if (Test-Path -Path $candidate -PathType Leaf) { $source = $candidate; break }
			}
			if (-not $source) {
				$plan.Notes += "[$($destination.Path)]: $($item.Name) has none of $(@($destination.Files) -join ', ') - left out"
				$plan.Destinations += $planDestination
				continue
			}
			$planDestination.Items += @{ Kind = $kindName; Name = $item.Name; Source = $source; Target = $destination.Path; WSLTarget = $destination.WSLPath }
			$plan.Destinations += $planDestination
			continue
		}

		foreach ($item in $items.Values) {
			$source = $null
			$linkName = $item.Name
			foreach ($file in $destination.Files) {
				if ($file -eq '.') { $source = $item.Path; break }
				$candidate = Join-Path $item.Path $file
				if (Test-Path -Path $candidate -PathType Leaf) {
					$source = $candidate
					$dot = $file.IndexOf('.')
					if ($dot -ge 0) { $linkName = $item.Name + $file.Substring($dot) }
					break
				}
			}
			if (-not $source) { continue }
			$wslTarget = if ($destination.WSLPath) { $destination.WSLPath.TrimEnd('/') + "/$linkName" } else { '' }
			$planDestination.Items += @{ Kind = $kindName; Name = $item.Name; Source = $source; Target = (Join-Path $destination.Path $linkName); WSLTarget = $wslTarget }
		}
		$plan.Destinations += $planDestination
	}

	# Repository-scoped skills: linked into each repository's own .claude\skills.
	if ($wanted -contains 'skills' -and @($Config.Deploy) -contains 'claude-code') {
		$repoRoster = Get-AiArtifactRoster -Kind 'skills' -Config $Config
		if (-not $rosters.ContainsKey('skills')) {
			foreach ($problem in @($repoRoster.Problems)) { $plan.Warnings += $problem }
		}
		$byRepository = [ordered]@{}
		foreach ($item in @($repoRoster.Repo)) {
			if (-not $byRepository.Contains($item.Repository)) { $byRepository[$item.Repository] = @() }
			$byRepository[$item.Repository] += $item
		}
		foreach ($repository in $byRepository.Keys) {
			# Resolve-RepositoryTargets returns its list comma-wrapped; the assignment unwraps it.
			$targets = Resolve-RepositoryTargets -Repositories $repository
			$target = @($targets) | Where-Object { $_ -and $_.Name -eq $repository } | Select-Object -First 1
			if (-not $target -or -not $target.LocalPath) {
				$plan.Warnings += "Repository [$repository] of a repo:$repository manifest row is not in RepositoryGroups - its skills were left out"
				continue
			}
			if (-not (Test-Path -LiteralPath $target.LocalPath -PathType Container)) {
				$plan.Notes += "Repository [$repository] is not cloned at [$($target.LocalPath)] - its skills were left out"
				continue
			}
			$path = Join-Path $target.LocalPath '.claude\skills'
			$planDestination = @{
				Harness    = "repo:$repository"
				Kind       = 'skills'
				Placement  = 'each'
				Hooks      = @('git-exclude')
				Path       = $path
				WSLPath    = ''
				Repository = [string]$target.LocalPath
				Items      = @()
			}
			$seen = @{}
			foreach ($item in $byRepository[$repository]) {
				if ($seen.ContainsKey($item.Name.ToLowerInvariant())) {
					$plan.Warnings += "Duplicate skill [$($item.Name)] for repository [$repository] in source [$($item.Source)] - keeping the first"
					continue
				}
				$seen[$item.Name.ToLowerInvariant()] = $true
				$planDestination.Items += @{ Kind = 'skills'; Name = $item.Name; Source = $item.Path; Target = (Join-Path $path $item.Name); WSLTarget = '' }
			}
			$plan.Destinations += $planDestination
		}
	}

	return $plan
}

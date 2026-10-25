function Get-AiArtifactRoster {
	<#
	.SYNOPSIS
		Enumerates the AI artifacts of one kind under the artifacts root, flattened by item name.

	.DESCRIPTION
		Every app discovers its skills, mods, prompts and agents from one flat folder, so the
		repository's <Root>\<Kind>\<source>\<item> tree has to be flattened before it can be
		linked or listed - and every reading has to flatten it the same way, or List-AiArtifacts
		would report a roster Deploy-AiArtifacts does not deploy. This is that single reading:

		  - The sources read, in order: `own` first (your own items), then, in name order,
		    `winux` (the product skills), `example` (the example rules) and every source
		    AiArtifacts.Sources configures. Any other source folder is not read.
		  - An item is a folder: a skill holds SKILL.md, a mod .claude-plugin\plugin.json, a
		    rules, prompt or agent item at least one file that does not start with a dot (its
		    per-app variants: RULES.md, claude.md, managed-settings.json, ...).
		  - The Exclude entries apply: kind/name drops the item from every source,
		    kind/source/name from that source only. Names compare case-insensitively.
		  - When two sources carry the same item name, the first source wins.

		Returns:

		  Root        The artifacts root the roster was read from.
		  Kind        The kind, lowercased.
		  Items       An ordered map of item name -> @{ Name; Path; Source; Kind }, in the order
		              the walk found them (source order, then item name).
		  Duplicates  One entry per losing name -> @{ Name; Source; KeptFrom }, so a caller can
		              report the collision in its own voice.

		A missing root or kind folder is not an error: it yields an empty roster.

	.PARAMETER Kind
		The kind to read: Skills, Mods, Rules, Prompts or Agents.

	.PARAMETER Config
		A resolved configuration (Resolve-AiArtifactsConfig). Defaults to resolving the global one.

	.EXAMPLE
		(Get-AiArtifactRoster -Kind Skills).Items.Count
		Returns how many distinct skills this machine deploys.

	.EXAMPLE
		(Get-AiArtifactRoster -Kind Rules).Items['CoreAiRules'].Source
		Returns e.g. "own" when your own rules shadow the example.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Skills', 'Mods', 'Rules', 'Prompts', 'Agents')]
		[string]$Kind,

		[Parameter()]
		[hashtable]$Config
	)

	if (-not $Config) {
		$Config = Resolve-AiArtifactsConfig
	}

	$kindName = $Kind.ToLowerInvariant()
	$folder = (Get-Culture).TextInfo.ToTitleCase($kindName)
	$base = Join-Path $Config.Root $folder

	$roster = @{
		Root       = $Config.Root
		Kind       = $kindName
		Items      = [ordered]@{}
		Duplicates = @()
	}

	if (-not (Test-Path -Path $base -PathType Container)) {
		return $roster
	}

	$allowed = @('winux', 'example') + @($Config.Sources.Keys | ForEach-Object { ([string]$_).ToLowerInvariant() })
	$sourceDirs = @(Get-ChildItem -Path $base -Directory | Where-Object { $_.Name -ne 'own' -and $allowed -contains $_.Name.ToLowerInvariant() } | Sort-Object Name)
	$own = Get-Item -Path (Join-Path $base 'own') -ErrorAction SilentlyContinue
	if ($own -and $own.PSIsContainer) {
		$sourceDirs = @($own) + $sourceDirs
	}

	$exclude = @($Config.Exclude)
	foreach ($sourceDir in $sourceDirs) {
		foreach ($itemDir in (Get-ChildItem -Path $sourceDir.FullName -Directory | Sort-Object Name)) {
			$isItem = switch ($kindName) {
				'skills' { Test-Path -Path (Join-Path $itemDir.FullName 'SKILL.md') -PathType Leaf }
				'mods' { Test-Path -Path (Join-Path $itemDir.FullName '.claude-plugin\plugin.json') -PathType Leaf }
				default { @(Get-ChildItem -Path $itemDir.FullName -File | Where-Object { -not $_.Name.StartsWith('.') }).Count -gt 0 }
			}
			if (-not $isItem) { continue }

			$lower = $itemDir.Name.ToLowerInvariant()
			if ($exclude -contains "$kindName/$lower" -or $exclude -contains "$kindName/$($sourceDir.Name.ToLowerInvariant())/$lower") {
				continue
			}

			$existing = @($roster.Items.Keys | Where-Object { $_ -eq $itemDir.Name }) | Select-Object -First 1
			if ($null -ne $existing) {
				$roster.Duplicates += @{
					Name     = $itemDir.Name
					Source   = $sourceDir.Name
					KeptFrom = $roster.Items[$existing].Source
				}
				continue
			}
			$roster.Items[$itemDir.Name] = @{
				Name   = $itemDir.Name
				Path   = $itemDir.FullName
				Source = $sourceDir.Name
				Kind   = $kindName
			}
		}
	}

	return $roster
}

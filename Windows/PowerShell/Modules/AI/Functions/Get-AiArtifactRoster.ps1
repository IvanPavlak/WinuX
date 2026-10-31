function Get-AiArtifactRoster {
	<#
	.SYNOPSIS
		Enumerates the AI artifacts of one kind from every source, flattened by item name.

	.DESCRIPTION
		Every app discovers its skills, mods, prompts and agents from one flat folder, so the
		sources have to be flattened before they can be linked or listed - and every reading has
		to flatten them the same way, or List-AiArtifacts would report a roster
		Deploy-AiArtifacts does not deploy. This is that single reading.

		Sources, in precedence order (the first wins an item name two carry):

		  1. own        <Root>\<Kind>\own\ - your own items
		  2. checkout   every AiArtifacts.Checkouts entry, in name order: the items under the
		                kind's folders of a local repository, linked straight from it
		  3. product    <Root>\<Kind>\winux\ - the skills WinuX ships
		  4. example    <Root>\<Kind>\example\ - the example rules
		  5. vendored   <Root>\<Kind>\<name>\ of every AiArtifacts.Sources entry, in name order
		  6. manifest   every AiArtifacts.Manifests entry, in name order: the rows of its
		                manifest for this kind whose scope is * or the active AI profile, linked
		                from the manifest cache (<CacheRoot>\<owner>\<repo>\<ref>\<path>, or the
		                derived copy <ref>.derived\<link-name> of a strip-invocation-guard or
		                rename= row) under their rename= name. A manifest item's source is
		                its upstream owner, lowercased (the <owner> of https://github.com/
		                <owner>/<repo>), so kind/<owner>/name matches that upstream's rows
		                only; a checkout item's source is the checkout source's name

		Any other folder under <Root>\<Kind>\ is not read. An item is a folder: a skill holds
		SKILL.md, a mod .claude-plugin\plugin.json, a rules, prompt or agent item at least one
		file that does not start with a dot. The Exclude entries apply (kind/name drops the item
		from every source, kind/source/name from that source only; wildcards allowed), and the
		Include entries limit a kind they name (kind/name or kind/source/name) to the items they
		match. Names compare case-insensitively.

		A manifest row scoped repo:<name> is not part of the flat roster: it goes into Repo,
		for Deploy-AiArtifacts to link into that repository's .claude\skills\ (skills only).

		Returns:

		  Root        The artifacts root the roster was read from.
		  Kind        The kind, lowercased.
		  Items       An ordered map of item name -> @{ Name; Path; Source; SourceKind; Kind;
		              Manifest }, in precedence order. SourceKind is own, checkout, product,
		              example, vendored or manifest; Manifest is the manifest source's name
		              (manifest items only).
		  Duplicates  One entry per losing name -> @{ Name; Source; KeptFrom }.
		  Repo        The repo:<name> manifest items -> @{ Repository; Name; Path; Source;
		              SourceKind; Manifest; Kind }.
		  Problems    Manifest problems and rows whose pinned ref is not in the cache yet.

		A missing root, kind folder, checkout or manifest is not an error: it yields fewer items.

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
		Repo       = @()
		Problems   = @()
	}

	$exclude = @($Config.Exclude | Where-Object { $_ })
	$include = @($Config.Include | Where-Object { $_ -and ([string]$_).StartsWith("$kindName/") })
	$profileName = if ($Config.Profile -and $Config.Profile.Enabled) { [string]$Config.Profile.Name } else { '' }

	# Candidates in precedence order: @{ Name; Path; Source; SourceKind }.
	$candidates = [Collections.Generic.List[hashtable]]::new()
	$readFolder = {
		param([string]$Folder, [string]$SourceName, [string]$SourceKind)
		if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return }
		foreach ($itemDir in (Get-ChildItem -LiteralPath $Folder -Directory | Sort-Object Name)) {
			$candidates.Add(@{ Name = $itemDir.Name; Path = $itemDir.FullName; Source = $SourceName; SourceKind = $SourceKind })
		}
	}

	$sourceDirs = @{}
	if (Test-Path -LiteralPath $base -PathType Container) {
		foreach ($dir in (Get-ChildItem -LiteralPath $base -Directory)) { $sourceDirs[$dir.Name.ToLowerInvariant()] = $dir }
	}

	# 1. own
	if ($sourceDirs.ContainsKey('own')) { & $readFolder $sourceDirs['own'].FullName $sourceDirs['own'].Name 'own' }

	# 2. checkout sources
	if ($Config.Checkouts -is [System.Collections.IDictionary]) {
		foreach ($checkout in $Config.Checkouts.Values) {
			if (-not $checkout.Kinds.Contains($kindName)) { continue }
			foreach ($relative in @($checkout.Kinds[$kindName])) {
				$path = if ($relative -eq '.') { $checkout.Path } else { Join-Path $checkout.Path ($relative.Replace('/', '\')) }
				& $readFolder $path $checkout.Name 'checkout'
			}
		}
	}

	# 3. product, 4. example, 5. vendored sources in name order
	if ($sourceDirs.ContainsKey('winux')) { & $readFolder $sourceDirs['winux'].FullName $sourceDirs['winux'].Name 'product' }
	if ($sourceDirs.ContainsKey('example')) { & $readFolder $sourceDirs['example'].FullName $sourceDirs['example'].Name 'example' }
	if ($Config.Sources -is [System.Collections.IDictionary]) {
		foreach ($sourceName in (@($Config.Sources.Keys) | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)) {
			if (@('own', 'winux', 'example') -contains $sourceName) { continue }
			if ($sourceDirs.ContainsKey($sourceName)) { & $readFolder $sourceDirs[$sourceName].FullName $sourceDirs[$sourceName].Name 'vendored' }
		}
	}

	# 6. manifest sources
	if ($Config.Manifests -is [System.Collections.IDictionary]) {
		foreach ($manifestSource in $Config.Manifests.Values) {
			if (-not (Test-Path -LiteralPath $manifestSource.Path -PathType Leaf)) {
				$roster.Problems += "[$($manifestSource.Name)] manifest not found => [$($manifestSource.Path)]"
				continue
			}
			$manifest = Get-AiArtifactManifest -Path $manifestSource.Path
			foreach ($problem in $manifest.Problems) { $roster.Problems += "[$($manifestSource.Name)] $problem" }
			foreach ($row in $manifest.Rows) {
				if ($row.Kind -ne $kindName) { continue }
				$isRepo = [bool]$row.Repository
				$applies = $isRepo -or ($row.Scope -contains '*') -or ($profileName -and @($row.Scope | Where-Object { $_ -eq $profileName }).Count -gt 0)
				if (-not $applies) { continue }
				$refFolder = Join-Path $Config.CacheRoot "$($row.Owner)\$($row.Repo)\$($row.Ref)"
				# A strip-invocation-guard or rename= row is linked from its derived copy.
				$path = if ($row.StripInvocationGuard -or $row.Rename) { Join-Path "$refFolder.derived" $row.LinkName } else { Join-Path $refFolder ($row.Path.Replace('/', '\')) }
				if (-not (Test-Path -LiteralPath $path -PathType Container)) {
					$roster.Problems += "[$($manifestSource.Name)] $kindName/$($row.LinkName) is not in the manifest cache yet ($($row.Owner)/$($row.Repo)@$($row.Ref.Substring(0, 7))) - run Update-AiArtifacts"
					continue
				}
				if ($isRepo) {
					if ($kindName -ne 'skills') {
						$roster.Problems += "[$($manifestSource.Name)] $kindName/$($row.LinkName) is scoped [repo:$($row.Repository)], which only skills take - skipped"
						continue
					}
					$roster.Repo += @{ Repository = $row.Repository; Name = $row.LinkName; Path = $path; Source = $row.Owner.ToLowerInvariant(); SourceKind = 'manifest'; Manifest = $manifestSource.Name; Kind = $kindName }
					continue
				}
				# A manifest item is labelled by its upstream owner, as a vendored source is by its folder,
				# so kind/<owner>/name matches exactly that upstream's rows.
				$candidates.Add(@{ Name = $row.LinkName; Path = $path; Source = $row.Owner.ToLowerInvariant(); SourceKind = 'manifest'; Manifest = $manifestSource.Name })
			}
		}
	}

	foreach ($candidate in $candidates) {
		$isItem = switch ($kindName) {
			'skills' { Test-Path -LiteralPath (Join-Path $candidate.Path 'SKILL.md') -PathType Leaf }
			'mods' { Test-Path -LiteralPath (Join-Path $candidate.Path '.claude-plugin\plugin.json') -PathType Leaf }
			default { @(Get-ChildItem -LiteralPath $candidate.Path -File | Where-Object { -not $_.Name.StartsWith('.') }).Count -gt 0 }
		}
		if (-not $isItem) { continue }

		$lower = $candidate.Name.ToLowerInvariant()
		$keys = @("$kindName/$lower", "$kindName/$($candidate.Source.ToLowerInvariant())/$lower")
		if (@($exclude | Where-Object { $pattern = $_; @($keys | Where-Object { $_ -like $pattern }).Count -gt 0 }).Count -gt 0) {
			continue
		}
		if ($include.Count -gt 0 -and @($include | Where-Object { $pattern = $_; @($keys | Where-Object { $_ -like $pattern }).Count -gt 0 }).Count -eq 0) {
			continue
		}

		$existing = @($roster.Items.Keys | Where-Object { $_ -eq $candidate.Name }) | Select-Object -First 1
		if ($null -ne $existing) {
			$roster.Duplicates += @{
				Name     = $candidate.Name
				Source   = $candidate.Source
				KeptFrom = $roster.Items[$existing].Source
			}
			continue
		}
		$roster.Items[$candidate.Name] = @{
			Name       = $candidate.Name
			Path       = $candidate.Path
			Source     = $candidate.Source
			SourceKind = $candidate.SourceKind
			Manifest   = [string]$candidate.Manifest
			Kind       = $kindName
		}
	}

	return $roster
}

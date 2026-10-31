function Sync-AiManifestCache {
	<#
	.SYNOPSIS
		Clones the pinned refs of the manifest sources into the manifest cache, and with -Check reports the rows whose upstream has moved on.

	.DESCRIPTION
		A manifest source (AiArtifacts.Manifests) names a manifest file (Get-AiArtifactManifest)
		whose rows pin third-party items to a commit. Their items are never copied into the
		repository: each source + ref is cloned once into the cache, outside every repository,
		at <CacheRoot>\<owner>\<repo>\<ref>\ (%LOCALAPPDATA%\WinuX\ai-manifests), and
		Deploy-AiArtifacts links the items from there. A ref is immutable, so a clone that is
		there is never fetched again; a clone is made in <ref>.partial and renamed only once its
		checkout succeeded, so a broken fetch never looks complete. Only the pinned commit is
		fetched (a shallow fetch by id, the full clone only when the server refuses that), each
		fetch is announced as it starts, and git's credential prompts are off, so a private or
		renamed upstream fails at once instead of waiting.

		Only the rows that apply here are fetched: scope * or the active AI profile's name, and
		every repo:<name> row (with profiles off, * and repo: rows only). A row with
		strip-invocation-guard or rename=<new-name> gets a derived copy of its item in
		<CacheRoot>\<owner>\<repo>\<ref>.derived\<link-name>\ (the rename= name, else the row's
		name): strip-invocation-guard removes the disable-model-invocation line from the
		frontmatter of its SKILL.md, so agents can call the skill, and rename= rewrites the
		frontmatter name: to the new name, since Claude Code names a skill by its frontmatter,
		not its folder. It is made once, like the clone.

		-Check fetches nothing: for every source of the rows that apply it asks the upstream for
		its default branch head (`git ls-remote <source> HEAD`) and reports each row whose
		pinned ref is not that head.

		Returns @{ Fetched; Present; Failed; Behind; Problems }: the cache folders cloned now,
		the ones already there, the source@ref pairs that failed, the rows -Check found behind
		(@{ Manifest; Name; Kind; Source; Ref; Head }), and the manifest problems.

	.PARAMETER Config
		A resolved configuration (Resolve-AiArtifactsConfig). Defaults to resolving the global one.

	.PARAMETER Source
		Limits the work to these manifest sources. Defaults to every manifest source.

	.PARAMETER Check
		Reports rows whose upstream default branch has moved past the pinned ref, changing nothing.

	.EXAMPLE
		Sync-AiManifestCache
		Clones every missing pinned ref of the manifest sources.

	.EXAMPLE
		(Sync-AiManifestCache -Check).Behind
		Lists the manifest rows whose upstream has newer commits.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[hashtable]$Config,

		[Parameter()]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	if (-not $Config) {
		$Config = Resolve-AiArtifactsConfig
	}

	$result = @{
		Fetched  = @()
		Present  = @()
		Failed   = @()
		Behind   = @()
		Problems = @()
	}

	$manifests = if ($Config.Manifests -is [System.Collections.IDictionary]) { $Config.Manifests } else { @{} }
	if ($manifests.Count -eq 0) { return $result }

	$profileName = if ($Config.Profile -and $Config.Profile.Enabled) { [string]$Config.Profile.Name } else { '' }
	$cacheRoot = [string]$Config.CacheRoot

	# Rows that apply on this machine, keyed by the cache folder they need.
	$wanted = [ordered]@{}
	foreach ($manifestName in @($manifests.Keys)) {
		if ($Source -and @($Source | Where-Object { $_ -eq $manifestName }).Count -eq 0) { continue }
		$manifest = Get-AiArtifactManifest -Path $manifests[$manifestName].Path
		foreach ($problem in $manifest.Problems) { $result.Problems += "[$manifestName] $problem" }
		foreach ($row in $manifest.Rows) {
			$applies = $row.Repository -or ($row.Scope -contains '*') -or ($profileName -and @($row.Scope | Where-Object { $_ -eq $profileName }).Count -gt 0)
			if (-not $applies) { continue }
			$key = "$($row.Owner)/$($row.Repo)/$($row.Ref)"
			if (-not $wanted.Contains($key)) {
				$wanted[$key] = @{
					Source = $row.Source
					Ref    = $row.Ref
					Folder = Join-Path $cacheRoot "$($row.Owner)\$($row.Repo)\$($row.Ref)"
					Rows   = @()
				}
			}
			$wanted[$key].Rows += @{ Manifest = $manifestName; Row = $row }
		}
	}

	if ($Check) {
		$heads = @{}
		foreach ($entry in $wanted.Values) {
			if (-not $heads.ContainsKey($entry.Source)) {
				$global:LASTEXITCODE = 0
				$output = @(& git ls-remote $entry.Source HEAD 2>$null)
				$head = ''
				if ($LASTEXITCODE -eq 0) {
					$first = @($output | Where-Object { $_ -match '^[0-9a-f]{40}\s' }) | Select-Object -First 1
					if ($first) { $head = ([string]$first).Substring(0, 40) }
				}
				$heads[$entry.Source] = $head
				if (-not $head) { $result.Failed += "$($entry.Source) (ls-remote)" }
			}
			$head = $heads[$entry.Source]
			if (-not $head -or $head -eq $entry.Ref) { continue }
			foreach ($use in $entry.Rows) {
				$result.Behind += @{
					Manifest = $use.Manifest
					Name     = $use.Row.LinkName
					Kind     = $use.Row.Kind
					Source   = $entry.Source
					Ref      = $entry.Ref
					Head     = $head
				}
			}
		}
		return $result
	}

	foreach ($entry in $wanted.Values) {
		$folder = $entry.Folder
		if (Test-Path -LiteralPath $folder -PathType Container) {
			$result.Present += $folder
		}
		else {
			$partial = "$folder.partial"
			Write-LogStep "Fetching manifest ref => [$($entry.Source)@$($entry.Ref.Substring(0, 7))]"
			# git must fail instead of waiting for a credential prompt nobody sees (a private or
			# renamed upstream), so both of its prompts are off for these calls.
			$savedPrompt = $env:GIT_TERMINAL_PROMPT
			$savedGcm = $env:GCM_INTERACTIVE
			$env:GIT_TERMINAL_PROMPT = '0'
			$env:GCM_INTERACTIVE = 'never'
			try {
				if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force }
				New-Item -ItemType Directory -Path $partial -Force | Out-Null
				# Only the pinned commit, no history: a full clone of some upstreams is gigabytes
				# of history for a tree of a few megabytes.
				$global:LASTEXITCODE = 0
				& git -C $partial init --quiet 2>$null | Out-Null
				if ($LASTEXITCODE -eq 0) { & git -C $partial fetch --quiet --depth 1 $entry.Source $entry.Ref 2>$null | Out-Null }
				if ($LASTEXITCODE -eq 0) { & git -C $partial -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD 2>$null | Out-Null }
				if ($LASTEXITCODE -ne 0) {
					# A server that refuses to fetch a commit by id: the full clone, then the pin.
					Remove-Item -LiteralPath $partial -Recurse -Force
					$global:LASTEXITCODE = 0
					& git clone --quiet --no-checkout $entry.Source $partial 2>$null | Out-Null
					if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit code $LASTEXITCODE)" }
					& git -C $partial -c advice.detachedHead=false checkout --quiet --detach $entry.Ref 2>$null | Out-Null
					if ($LASTEXITCODE -ne 0) { throw "git checkout $($entry.Ref) failed (exit code $LASTEXITCODE)" }
				}
				Rename-Item -LiteralPath $partial -NewName (Split-Path -Leaf $folder)
				$result.Fetched += $folder
			}
			catch {
				$result.Failed += "$($entry.Source)@$($entry.Ref) => $($_.Exception.Message)"
				if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue }
				continue
			}
			finally {
				$env:GIT_TERMINAL_PROMPT = $savedPrompt
				$env:GCM_INTERACTIVE = $savedGcm
			}
		}

		# Derived copies, made once per ref like the clone.
		foreach ($use in $entry.Rows) {
			$row = $use.Row
			if (-not $row.StripInvocationGuard -and -not $row.Rename) { continue }
			$derived = Join-Path "$folder.derived" $row.LinkName
			if (Test-Path -LiteralPath $derived -PathType Container) { continue }
			$item = Join-Path $folder ($row.Path.Replace('/', '\'))
			if (-not (Test-Path -LiteralPath $item -PathType Container)) {
				$result.Problems += "[$($use.Manifest)] $($row.Kind)/$($row.Name): [$($row.Path)] is not a folder at $($row.Ref) - not derived"
				continue
			}
			try {
				New-Item -ItemType Directory -Path "$folder.derived" -Force | Out-Null
				Copy-Item -LiteralPath $item -Destination $derived -Recurse -Force
				$gitLink = Join-Path $derived '.git'
				if (Test-Path -LiteralPath $gitLink) { Remove-Item -LiteralPath $gitLink -Recurse -Force }
				$skillFile = Join-Path $derived 'SKILL.md'
				if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
					$text = [IO.File]::ReadAllText($skillFile)
					$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
					$lines = $text -split "`r?`n"
					$kept = [Collections.Generic.List[string]]::new()
					$fence = 0
					foreach ($line in $lines) {
						if ($line.Trim() -eq '---' -and $fence -lt 2) { $fence++ }
						elseif ($fence -eq 1 -and $row.StripInvocationGuard -and $line -match '^\s*disable-model-invocation\s*:') { continue }
						elseif ($fence -eq 1 -and $row.Rename -and $line -match '^(\s*)name\s*:') {
							# Claude Code names a skill by its frontmatter, not its folder.
							$kept.Add("$($Matches[1])name: $($row.LinkName)")
							continue
						}
						$kept.Add($line)
					}
					[IO.File]::WriteAllText($skillFile, ($kept -join $newline), [Text.UTF8Encoding]::new($false))
				}
			}
			catch {
				$result.Problems += "[$($use.Manifest)] $($row.Kind)/$($row.Name): the derived copy failed => $($_.Exception.Message)"
				if (Test-Path -LiteralPath $derived) { Remove-Item -LiteralPath $derived -Recurse -Force -ErrorAction SilentlyContinue }
			}
		}
	}

	return $result
}

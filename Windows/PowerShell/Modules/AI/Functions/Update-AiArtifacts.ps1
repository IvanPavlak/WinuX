function Update-AiArtifacts {
	<#
	.SYNOPSIS
		Vendors AI skills, mods, rules, prompts and agents from the configured upstream repositories into the artifacts root, pinned.

	.DESCRIPTION
		For each AiArtifacts.Sources entry (all, or the ones -Source names) it resolves Ref to an
		exact commit through the GitHub API, downloads that commit's archive once, and, for every
		kind the entry names (Skills, Mods, Rules, Prompts, Agents = upstream folders, "." for
		the repository root; no kind key: Skills = @("skills")), copies the items found under
		those folders into <Root>\<Kind>\<name>\:

		  Skills   every folder holding SKILL.md (a folder that holds one itself, else its
		           subfolders; the category level of an upstream is dropped)
		  Mods     a folder that itself holds .claude-plugin\plugin.json is one mod, else each
		           subfolder holding it is; named by its plugin.json `name` (else the folder name,
		           or the repository name for a root mod)
		  Rules, Prompts, Agents
		           every subfolder is one item; a top-level NAME.md file (not README, CHANGELOG or
		           LICENSE) becomes item NAME holding it as RULES.md, PROMPT.md or AGENT.md

		without the entry's Exclude items and without the top-level entries of an item listed in
		SkipPaths (default .git, .github, tests, design, docs). Provenance goes into
		<Root>\<Kind>\<name>\UPSTREAM.md (repository, resolved commit, fetch time, folders,
		exclusions, skipped paths, and a table of every vendored item with its description), in
		the format Get-AiSkillManifest reads, and the upstream LICENSE is copied next to it.

		SAFETY: only the item folders named in the PREVIOUS UPSTREAM.md (plus the ones about to be
		written) are removed before copying, so a folder added by hand inside a source folder
		survives a refresh. Your own items belong in <Root>\<Kind>\own\, which no refresh touches.

		-Check compares each manifest's pinned commit with the current upstream head of Ref and
		reports whether the vendored copy is behind, without downloading or writing anything.

		Private repositories: when a GitHub token is available, both requests authenticate with
		it and the archive is fetched through the API's zipball endpoint, which accepts a token.
		The token is the GITHUB_TOKEN environment variable, else GH_TOKEN, else the output of
		`gh auth token` when the GitHub CLI is installed and signed in; it is sent only to
		api.github.com and never logged.

		Deprecated AiSkills.Sources and AiMods.Sources entries are read as sources through
		Resolve-AiArtifactsConfig. Not a Bootstrap step: the vendored tree is committed, so a fresh
		machine only needs Deploy-AiArtifacts. A network failure is reported per source and leaves
		that source's vendored copy untouched. The base configuration ships no sources.

	.PARAMETER Source
		Names of the configured sources to refresh. Defaults to every source.

	.PARAMETER Check
		Report whether each source's vendored copy is behind its upstream Ref, changing nothing.

	.EXAMPLE
		Update-AiArtifacts
		Refreshes every configured source to the current head of its Ref, then review the diff.

	.EXAMPLE
		Update-AiArtifacts -Source mattpocock
		Refreshes one source.

	.EXAMPLE
		Update-AiArtifacts -Check
		Prints, per source and kind, the pinned commit and whether upstream has moved.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	Write-LogTitle "Updating AI Artifacts"

	$config = Resolve-AiArtifactsConfig
	foreach ($message in @($config.Legacy | Where-Object { $_ -like '*.Sources.*' })) {
		Write-LogWarning $message
	}
	$sources = $config.Sources

	if ($sources.Count -eq 0) {
		Write-LogWarning "No AI artifact sources configured (AiArtifacts.Sources) - nothing to vendor!"
		return
	}

	$names = if ($Source) { @($Source) } else { @($sources.Keys | Sort-Object) }
	$failures = 0

	# One token for every source, so a private upstream resolves and downloads; never logged.
	$token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
	if (-not $token -and (Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue)) {
		$token = [string](& gh auth token 2>$null | Select-Object -First 1)
		if ($LASTEXITCODE -ne 0 -or -not $token.Trim()) { $token = $null }
	}
	$headers = @{}
	if ($token) {
		$headers['Authorization'] = "Bearer $(([string]$token).Trim())"
	}

	$portable = @{ rules = 'RULES.md'; prompts = 'PROMPT.md'; agents = 'AGENT.md' }

	foreach ($requested in $names) {
		$name = @($sources.Keys | Where-Object { $_ -eq $requested }) | Select-Object -First 1
		if (-not $name) {
			Write-LogError "Unknown AI artifact source => [$requested] (configured: $(($sources.Keys | Sort-Object) -join ', '))"
			$failures++
			continue
		}

		$entry = $sources[$name]
		$repository = $entry.Repository
		$ref = $entry.Ref
		$exclude = @($entry.Exclude)
		$skipPaths = @($entry.SkipPaths)

		if ($repository -notmatch '^[\w.-]+/[\w.-]+$') {
			Write-LogError "Source [$name] needs Repository in owner/name form => [$repository]"
			$failures++
			continue
		}

		Write-LogStep "[$name] $repository @ $ref => $($entry.Kinds.Keys -join ', ')"

		$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-artifacts-$name"
		$zipPath = Join-Path $tempRoot "source.zip"
		$extractPath = Join-Path $tempRoot "extract"

		try {
			# Resolve the ref to an exact commit first, so UPSTREAM.md always pins a sha and the
			# archive URL below is stable even when the ref is a moving branch.
			$commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/commits/$ref" -Headers $headers
			$sha = [string]$commit.sha
			if (-not $sha) {
				Write-LogError "[$name] Could not resolve [$ref] to a commit in [$repository]!"
				$failures++
				continue
			}

			if ($Check) {
				foreach ($kind in $entry.Kinds.Keys) {
					$folder = (Get-Culture).TextInfo.ToTitleCase($kind)
					$previous = Get-AiSkillManifest -Path (Join-Path $config.Root "$folder\$name\UPSTREAM.md")
					if (-not $previous.Commit) {
						Write-LogWarning "[$name] $kind not vendored yet - upstream head is $($sha.Substring(0, 7))"
					}
					elseif ($previous.Commit -eq $sha) {
						Write-LogSuccess "[$name] $kind up to date at $($sha.Substring(0, 7))"
					}
					else {
						Write-LogWarning "[$name] $kind behind upstream: vendored $($previous.Commit.Substring(0, 7)), head $($sha.Substring(0, 7)) - run Update-AiArtifacts -Source $name"
					}
				}
				continue
			}

			if (Test-Path -Path $tempRoot) {
				Remove-Item -Path $tempRoot -Recurse -Force
			}
			New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

			# Anonymous: the public archive URL. Authenticated: the API's zipball, which takes the
			# token and redirects to a signed download URL, so a private repository downloads too.
			$archiveUri = if ($token) { "https://api.github.com/repos/$repository/zipball/$sha" } else { "https://github.com/$repository/archive/$sha.zip" }
			Invoke-WebRequest -Uri $archiveUri -Headers $headers -OutFile $zipPath
			Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

			# GitHub archives unpack into a single <name>-<sha> folder.
			$sourceRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
			if (-not $sourceRoot) {
				Write-LogError "[$name] The downloaded archive is empty!"
				$failures++
				continue
			}

			$licenseName = "LICENSE.$($repository -replace '/', '-').txt"
			$upstreamLicense = Get-ChildItem -Path $sourceRoot.FullName -File -Filter "LICENSE*" | Select-Object -First 1

			foreach ($kind in $entry.Kinds.Keys) {
				$folders = @($entry.Kinds[$kind])
				$kindFolder = (Get-Culture).TextInfo.ToTitleCase($kind)
				$singular = $kindFolder.TrimEnd('s')
				$destination = Join-Path $config.Root "$kindFolder\$name"
				$manifestPath = Join-Path $destination "UPSTREAM.md"
				$previous = Get-AiSkillManifest -Path $manifestPath

				# Collect every item under the configured upstream folders, keyed by item name.
				$incoming = [ordered]@{}
				foreach ($folder in $folders) {
					$folderPath = if ($folder -eq '.') { $sourceRoot.FullName } else { Join-Path $sourceRoot.FullName ($folder -replace '/', '\') }
					if (-not (Test-Path -Path $folderPath -PathType Container)) {
						Write-LogWarning "[$name] Upstream $kind folder not found - skipped => [$folder]"
						continue
					}

					$found = @()
					switch ($kind) {
						'skills' {
							$candidates = @(Get-Item -Path $folderPath) + @(Get-ChildItem -Path $folderPath -Directory | Sort-Object Name)
							foreach ($dir in $candidates) {
								$skillFile = Join-Path $dir.FullName "SKILL.md"
								if (Test-Path -Path $skillFile -PathType Leaf) {
									$found += @{ Name = $dir.Name; Path = $dir.FullName; Description = Get-AiSkillDescription -SkillFile $skillFile }
								}
							}
						}
						'mods' {
							$candidates = if (Test-Path -Path (Join-Path $folderPath ".claude-plugin\plugin.json")) {
								@(Get-Item -Path $folderPath)
							}
							else {
								@(Get-ChildItem -Path $folderPath -Directory | Sort-Object Name | Where-Object { Test-Path -Path (Join-Path $_.FullName ".claude-plugin\plugin.json") })
							}
							foreach ($dir in $candidates) {
								$fallback = if ($dir.FullName -eq $sourceRoot.FullName) { ($repository -split '/')[1] } else { $dir.Name }
								$modName = $fallback
								$description = ""
								try {
									$plugin = Get-Content -Path (Join-Path $dir.FullName ".claude-plugin\plugin.json") -Raw | ConvertFrom-Json -ErrorAction Stop
									if ($plugin.name -and [string]$plugin.name -match '^[A-Za-z0-9._-]+$') { $modName = [string]$plugin.name }
									if ($plugin.description) { $description = ([string]$plugin.description) -replace '\|', '\|' -replace '\r?\n', ' ' }
								}
								catch {
									Write-LogWarning "[$name] Unreadable plugin.json - using the folder name => [$fallback]"
								}
								$found += @{ Name = $modName; Path = $dir.FullName; Description = $description }
							}
						}
						default {
							foreach ($dir in (Get-ChildItem -Path $folderPath -Directory | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)) {
								$first = Get-ChildItem -Path $dir.FullName -File -Filter "*.md" | Sort-Object Name | Select-Object -First 1
								$description = if ($first) { Get-AiSkillDescription -SkillFile $first.FullName } else { "" }
								$found += @{ Name = $dir.Name; Path = $dir.FullName; Description = $description }
							}
							foreach ($file in (Get-ChildItem -Path $folderPath -File -Filter "*.md" | Sort-Object Name)) {
								if ($file.Name -in @('README.md', 'CHANGELOG.md') -or $file.Name -like 'LICENSE*' -or $file.Name.StartsWith('.')) { continue }
								$found += @{ Name = $file.BaseName; Path = $file.FullName; Description = Get-AiSkillDescription -SkillFile $file.FullName }
							}
						}
					}

					foreach ($item in $found) {
						if ($exclude -contains $item.Name) {
							Write-LogStep "[$name] Excluded => $kind/$($item.Name)"
							continue
						}
						if ($incoming.Contains($item.Name)) {
							Write-LogWarning "[$name] Duplicate $($singular.ToLowerInvariant()) name across upstream folders - keeping the first => [$($item.Name)]"
							continue
						}
						$incoming[$item.Name] = @{ Path = $item.Path; Folder = $folder; Description = $item.Description }
					}
				}

				if ($incoming.Count -eq 0) {
					Write-LogError "[$name] No $kind found under [$($folders -join ', ')] - vendored copy left untouched!"
					$failures++
					continue
				}

				New-Item -ItemType Directory -Path $destination -Force | Out-Null

				# Remove only what the previous manifest says we vendored (plus incoming names, which
				# are about to be overwritten anyway). Anything else in the folder is never touched.
				foreach ($itemName in (@($previous.Skills) + @($incoming.Keys) | Sort-Object -Unique)) {
					$existing = Join-Path $destination $itemName
					if (Test-Path -Path $existing -PathType Container) {
						Remove-Item -Path $existing -Recurse -Force
					}
				}

				$rows = @()
				foreach ($itemName in ($incoming.Keys | Sort-Object)) {
					$item = $incoming[$itemName]
					$target = Join-Path $destination $itemName
					New-Item -ItemType Directory -Path $target -Force | Out-Null
					if (Test-Path -Path $item.Path -PathType Leaf) {
						Copy-Item -Path $item.Path -Destination (Join-Path $target $portable[$kind]) -Force
					}
					else {
						foreach ($child in Get-ChildItem -Path $item.Path -Force) {
							if ($skipPaths -contains $child.Name) { continue }
							Copy-Item -Path $child.FullName -Destination (Join-Path $target $child.Name) -Recurse -Force
						}
					}
					$rows += "| ``$itemName`` | ``$($item.Folder)`` | $($item.Description) |"
				}

				if ($upstreamLicense) {
					Copy-Item -Path $upstreamLicense.FullName -Destination (Join-Path $destination $licenseName) -Force
				}

				$excludedText = if ($exclude.Count -gt 0) { ($exclude | ForEach-Object { "``$_``" }) -join ", " } else { "none" }
				$skippedText = if ($skipPaths.Count -gt 0) { ($skipPaths | ForEach-Object { "``$_``" }) -join ", " } else { "none" }
				$foldersText = ($folders | ForEach-Object { "``$_``" }) -join ", "
				$manifest = @(
					"# Vendored AI ${kind}: $name",
					"",
					"Generated by ``Update-AiArtifacts`` - do not edit by hand, re-run ``Update-AiArtifacts $name`` to refresh. Deployed into the AI harnesses by ``Deploy-AiArtifacts``.",
					"",
					"- **Source:** https://github.com/$repository",
					"- **Commit:** ``$sha`` (ref ``$ref``)",
					"- **Fetched:** $((Get-Date).ToString('s'))",
					"- **Upstream folders:** $foldersText",
					"- **Excluded:** $excludedText",
					"- **Skipped paths:** $skippedText",
					"- **License:** ``$licenseName`` (upstream LICENSE, verbatim)",
					"",
					"| $singular | Upstream folder | Description |",
					"| $('-' * $singular.Length) | --------------- | ----------- |"
				) + $rows

				# LF and no BOM, so the file is the same on every machine whatever its line-ending settings.
				[IO.File]::WriteAllText($manifestPath, ($manifest -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

				$removed = @($previous.Skills | Where-Object { -not $incoming.Contains($_) })
				if ($removed.Count -gt 0) {
					Write-LogWarning "[$name] Removed $kind no longer vendored => [$($removed -join ', ')]"
				}

				Write-LogSuccess "[$name] Vendored $($incoming.Count) $kind from [$repository@$($sha.Substring(0, 7))]"
			}
		}
		catch {
			$message = $_.Exception.Message
			if (-not $token -and $message -match '404') {
				$message += " - if [$repository] is private, set GITHUB_TOKEN or sign in with 'gh auth login'"
			}
			Write-LogError "[$name] Updating AI artifacts failed => $message"
			$failures++
		}
		finally {
			if (Test-Path -Path $tempRoot) {
				Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}

	if ($failures -eq 0 -and -not $Check) {
		Write-LogSuccess "AI artifacts vendored - run Deploy-AiArtifacts (or Bootstrap) to link them into the harnesses!"
	}
	elseif ($failures -gt 0) {
		Write-LogError "AI artifacts update finished with $failures failure(s)!"
	}
}

function Update-AiMods {
	<#
	.SYNOPSIS
		Vendors Claude Code mods from the configured upstream repositories into the mods root, pinned.

	.DESCRIPTION
		Claude Code mods are function-hook plugins: a folder holding .claude-plugin\plugin.json
		and a hooks module, loaded from the folders named in CLAUDE_CODE_PLUGIN_DIRS. WinuX keeps
		mods under the AiMods.Root folder (default AI/Mods), one subfolder per source, and
		Deploy-AiMods links every mod into the harness directory. This function fills the source
		folders from upstream repositories, the way Update-AiSkills does for skills.

		For each configured source (AiMods.Sources.<name>: Repository, Ref, Folders, Exclude,
		SkipPaths) it resolves Ref to an exact commit through the GitHub API, downloads that
		commit's archive, and finds the mods under the source's Folders (default "." - the
		repository root):

		  - A folder that itself holds .claude-plugin\plugin.json is one mod (a repository whose
		    root is the mod).
		  - Otherwise every subfolder holding .claude-plugin\plugin.json is a mod.

		Each mod is named by its plugin.json `name` (falling back to the folder name, or to the
		repository name for a root mod) and copied to <Root>\<name>\<mod>\. Top-level entries of
		the mod listed in SkipPaths are not copied (default .git, .github, tests, design, docs),
		so a mod's tests, design assets and CI stay upstream and only what the engine loads is
		vendored. Exclude lists mod names to leave out.

		Provenance is recorded in <Root>\<name>\UPSTREAM.md in the same format Update-AiSkills
		writes (repository, resolved commit, fetch time, folders, exclusions, and a table of
		every vendored mod with the description from its plugin.json), so Get-AiSkillManifest
		reads it unchanged, and the upstream LICENSE is copied next to it.

		SAFETY: only the mod directories named in the PREVIOUS UPSTREAM.md (plus the ones about
		to be written) are removed before copying, so a folder added by hand inside a source
		folder survives a refresh. Hand-written mods belong in their own source folder without
		a manifest (the convention is <Root>\own\), which no refresh ever touches.

		-Check compares each manifest's pinned commit with the current upstream head of Ref and
		reports whether the vendored copy is behind, without downloading or writing anything.

		Not a Bootstrap step: the vendored tree is committed, so a fresh machine only needs
		Deploy-AiMods. A network failure is reported per source and leaves that source's
		vendored copy untouched. The base configuration ships no sources, so this no-ops until
		a fork configures one.

	.PARAMETER Source
		Names of the configured sources to refresh. Defaults to every source in AiMods.Sources.

	.PARAMETER Check
		Report whether each source's vendored copy is behind its upstream Ref, changing nothing.

	.EXAMPLE
		Update-AiMods
		Refreshes every configured source to the current head of its Ref, then review the diff.

	.EXAMPLE
		Update-AiMods -Source my-mod
		Refreshes one source.

	.EXAMPLE
		Update-AiMods -Check
		Prints, per source, the pinned commit and whether upstream has moved.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	Write-LogTitle "Updating AI Mods"

	$config = Resolve-AiModsConfig
	$sources = $config.Sources

	if ($sources.Count -eq 0) {
		Write-LogWarning "No AI mod sources configured (AiMods.Sources) - nothing to vendor!"
		return
	}

	$names = if ($Source) { @($Source) } else { @($sources.Keys | Sort-Object) }
	$failures = 0

	foreach ($name in $names) {
		if (-not $sources.ContainsKey($name)) {
			Write-LogError "Unknown AI mod source => [$name] (configured: $(($sources.Keys | Sort-Object) -join ', '))"
			$failures++
			continue
		}

		$entry = $sources[$name]
		$repository = [string]$entry.Repository
		$ref = if ($entry.Ref) { [string]$entry.Ref } else { "main" }
		$folders = if ($entry.Folders) { @($entry.Folders) } else { @(".") }
		$exclude = if ($entry.Exclude) { @($entry.Exclude) } else { @() }
		$skipPaths = if ($entry.ContainsKey('SkipPaths') -and $null -ne $entry.SkipPaths) { @($entry.SkipPaths) } else { @(".git", ".github", "tests", "design", "docs") }
		$destination = Join-Path $config.Root $name
		$manifestPath = Join-Path $destination "UPSTREAM.md"

		if ($repository -notmatch '^[\w.-]+/[\w.-]+$') {
			Write-LogError "Source [$name] needs Repository in owner/name form => [$repository]"
			$failures++
			continue
		}

		Write-LogStep "[$name] $repository @ $ref => $destination"

		$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-mods-$name"
		$zipPath = Join-Path $tempRoot "mods.zip"
		$extractPath = Join-Path $tempRoot "extract"

		try {
			# Resolve the ref to an exact commit first, so UPSTREAM.md always pins a sha and the
			# archive URL below is stable even when the ref is a moving branch.
			$commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/commits/$ref"
			$sha = [string]$commit.sha
			if (-not $sha) {
				Write-LogError "[$name] Could not resolve [$ref] to a commit in [$repository]!"
				$failures++
				continue
			}

			$previous = Get-AiSkillManifest -Path $manifestPath

			if ($Check) {
				if (-not $previous.Commit) {
					Write-LogWarning "[$name] Not vendored yet - upstream head is $($sha.Substring(0, 7))"
				}
				elseif ($previous.Commit -eq $sha) {
					Write-LogSuccess "[$name] Up to date at $($sha.Substring(0, 7))"
				}
				else {
					Write-LogWarning "[$name] Behind upstream: vendored $($previous.Commit.Substring(0, 7)), head $($sha.Substring(0, 7)) - run Update-AiMods -Source $name"
				}
				continue
			}

			if (Test-Path -Path $tempRoot) {
				Remove-Item -Path $tempRoot -Recurse -Force
			}
			New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

			Invoke-WebRequest -Uri "https://github.com/$repository/archive/$sha.zip" -OutFile $zipPath
			Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

			# GitHub archives unpack into a single <name>-<sha> folder.
			$sourceRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
			if (-not $sourceRoot) {
				Write-LogError "[$name] The downloaded archive is empty!"
				$failures++
				continue
			}

			# Collect every mod under the configured upstream folders, keyed by mod name.
			$incoming = @{}
			foreach ($folder in $folders) {
				$folderPath = if ($folder -eq '.') { $sourceRoot.FullName } else { Join-Path $sourceRoot.FullName ($folder -replace '/', '\') }
				if (-not (Test-Path -Path $folderPath)) {
					Write-LogWarning "[$name] Upstream folder not found - skipped => [$folder]"
					continue
				}

				# A folder that is itself a mod is taken whole; otherwise its subfolders are scanned.
				$candidates = if (Test-Path -Path (Join-Path $folderPath ".claude-plugin\plugin.json")) {
					@(Get-Item -Path $folderPath)
				}
				else {
					@(Get-ChildItem -Path $folderPath -Directory | Where-Object { Test-Path -Path (Join-Path $_.FullName ".claude-plugin\plugin.json") })
				}

				foreach ($modDir in $candidates) {
					$fallback = if ($modDir.FullName -eq $sourceRoot.FullName) { ($repository -split '/')[1] } else { $modDir.Name }
					$modName = $fallback
					$description = ""
					try {
						$plugin = Get-Content -Path (Join-Path $modDir.FullName ".claude-plugin\plugin.json") -Raw | ConvertFrom-Json -ErrorAction Stop
						if ($plugin.name -and [string]$plugin.name -match '^[A-Za-z0-9._-]+$') {
							$modName = [string]$plugin.name
						}
						if ($plugin.description) {
							$description = ([string]$plugin.description) -replace '\|', '\|' -replace '\r?\n', ' '
						}
					}
					catch {
						Write-LogWarning "[$name] Unreadable plugin.json - using the folder name => [$fallback]"
					}

					if ($exclude -contains $modName) {
						Write-LogStep "[$name] Excluded => $modName"
						continue
					}
					if ($incoming.ContainsKey($modName)) {
						Write-LogWarning "[$name] Duplicate mod name across upstream folders - keeping the first => [$modName]"
						continue
					}
					$incoming[$modName] = @{ Source = $modDir.FullName; Folder = $folder; Description = $description }
				}
			}

			if ($incoming.Count -eq 0) {
				Write-LogError "[$name] No mods found under [$($folders -join ', ')] - vendored copy left untouched!"
				$failures++
				continue
			}

			New-Item -ItemType Directory -Path $destination -Force | Out-Null

			# Remove only what the previous manifest says we vendored (plus incoming names, which
			# are about to be overwritten anyway). Anything else in the folder is never touched.
			foreach ($mod in (@($previous.Skills) + @($incoming.Keys) | Sort-Object -Unique)) {
				$existing = Join-Path $destination $mod
				if (Test-Path -Path $existing) {
					Remove-Item -Path $existing -Recurse -Force
				}
			}

			$rows = @()
			foreach ($mod in ($incoming.Keys | Sort-Object)) {
				$item = $incoming[$mod]
				$target = Join-Path $destination $mod
				New-Item -ItemType Directory -Path $target -Force | Out-Null
				foreach ($child in Get-ChildItem -Path $item.Source -Force) {
					if ($skipPaths -contains $child.Name) {
						continue
					}
					Copy-Item -Path $child.FullName -Destination (Join-Path $target $child.Name) -Recurse -Force
				}
				$rows += "| ``$mod`` | ``$($item.Folder)`` | $($item.Description) |"
			}

			$licenseName = "LICENSE.$($repository -replace '/', '-').txt"
			$upstreamLicense = Get-ChildItem -Path $sourceRoot.FullName -File -Filter "LICENSE*" | Select-Object -First 1
			if ($upstreamLicense) {
				Copy-Item -Path $upstreamLicense.FullName -Destination (Join-Path $destination $licenseName) -Force
			}

			$excludedText = if ($exclude.Count -gt 0) { ($exclude | ForEach-Object { "``$_``" }) -join ", " } else { "none" }
			$skippedText = if ($skipPaths.Count -gt 0) { ($skipPaths | ForEach-Object { "``$_``" }) -join ", " } else { "none" }
			$foldersText = ($folders | ForEach-Object { "``$_``" }) -join ", "
			$manifest = @(
				"# Vendored AI mods: $name",
				"",
				"Generated by ``Update-AiMods`` - do not edit by hand, re-run ``Update-AiMods -Source $name`` to refresh. Linked into Claude Code by ``Deploy-AiMods``.",
				"",
				"- **Source:** https://github.com/$repository",
				"- **Commit:** ``$sha`` (ref ``$ref``)",
				"- **Fetched:** $((Get-Date).ToString('s'))",
				"- **Upstream folders:** $foldersText",
				"- **Excluded:** $excludedText",
				"- **Skipped paths:** $skippedText",
				"- **License:** ``$licenseName`` (upstream LICENSE, verbatim)",
				"",
				"| Mod | Upstream folder | Description |",
				"| --- | --------------- | ----------- |"
			) + $rows

			Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8

			$removed = @($previous.Skills | Where-Object { -not $incoming.ContainsKey($_) })
			if ($removed.Count -gt 0) {
				Write-LogWarning "[$name] Removed mods no longer vendored => [$($removed -join ', ')]"
			}

			Write-LogSuccess "[$name] Vendored $($incoming.Count) mods from [$repository@$($sha.Substring(0, 7))]"
		}
		catch {
			Write-LogError "[$name] Updating AI mods failed => $($_.Exception.Message)"
			$failures++
		}
		finally {
			if (Test-Path -Path $tempRoot) {
				Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}

	if ($failures -eq 0 -and -not $Check) {
		Write-LogSuccess "AI mods vendored - run Deploy-AiMods (or Bootstrap) to link them into Claude Code!"
	}
	elseif ($failures -gt 0) {
		Write-LogError "AI mods update finished with $failures failure(s)!"
	}
}

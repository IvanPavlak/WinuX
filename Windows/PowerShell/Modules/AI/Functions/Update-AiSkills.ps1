function Update-AiSkills {
	<#
	.SYNOPSIS
		Vendors Agent Skills from the configured upstream repositories into the skills root, flat and pinned.

	.DESCRIPTION
		Agent Skills (a SKILL.md per folder) are the per-harness counterpart of CoreAiRules: Claude
		Code reads them from ~/.claude/skills, Codex CLI and Gemini CLI from ~/.agents/skills, and
		every harness wants a flat directory of <skill>/SKILL.md. WinuX keeps skills under the
		AiSkills.Root folder (default AI/Skills), one subfolder per source, and Deploy-AiSkills
		links every skill into every harness directory. This function fills the source folders.

		For each configured source (AiSkills.Sources.<name>: Repository, Ref, Folders, Exclude) it
		resolves Ref to an exact commit through the GitHub API, downloads that commit's archive,
		and copies every skill folder (a directory holding SKILL.md) found under the source's
		Folders FLAT into <Root>\<name>\ - upstreams nest skills by category
		(skills/engineering/grill-me), harnesses require <skill> at the top level, so the category
		level is dropped. Supporting files inside a skill are copied as they are.

		Provenance is recorded in <Root>\<name>\UPSTREAM.md (repository, resolved commit, fetch
		time, folders, exclusions, and a table of every vendored skill with the description parsed
		from its SKILL.md by Get-AiSkillDescription) and the upstream LICENSE is copied next to it.

		SAFETY: only the skill directories named in the PREVIOUS UPSTREAM.md (plus the ones about
		to be written) are removed before copying, so a folder added by hand inside a source
		folder survives a refresh. Hand-written skills belong in their own source folder without
		a manifest (the convention is <Root>\own\), which no refresh ever touches.

		-Check compares each manifest's pinned commit with the current upstream head of Ref and
		reports whether the vendored copy is behind, without downloading or writing anything.

		Not a Bootstrap step: the vendored tree is committed, so a fresh machine only needs
		Deploy-AiSkills. A network failure is reported per source and leaves that source's
		vendored copy untouched. The base configuration ships no sources, so this no-ops until
		a fork configures one.

	.PARAMETER Source
		Names of the configured sources to refresh. Defaults to every source in AiSkills.Sources.

	.PARAMETER Check
		Report whether each source's vendored copy is behind its upstream Ref, changing nothing.

	.EXAMPLE
		Update-AiSkills
		Refreshes every configured source to the current head of its Ref, then review the diff.

	.EXAMPLE
		Update-AiSkills -Source mattpocock
		Refreshes one source.

	.EXAMPLE
		Update-AiSkills -Check
		Prints, per source, the pinned commit and whether upstream has moved.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Source,

		[Parameter()]
		[switch]$Check
	)

	Write-LogTitle "Updating AI Skills"

	$config = Resolve-AiSkillsConfig
	$sources = $config.Sources

	if ($sources.Count -eq 0) {
		Write-LogWarning "No AI skill sources configured (AiSkills.Sources) - nothing to vendor!"
		return
	}

	$names = if ($Source) { @($Source) } else { @($sources.Keys | Sort-Object) }
	$failures = 0

	foreach ($name in $names) {
		if (-not $sources.ContainsKey($name)) {
			Write-LogError "Unknown AI skill source => [$name] (configured: $(($sources.Keys | Sort-Object) -join ', '))"
			$failures++
			continue
		}

		$entry = $sources[$name]
		$repository = [string]$entry.Repository
		$ref = if ($entry.Ref) { [string]$entry.Ref } else { "main" }
		$folders = if ($entry.Folders) { @($entry.Folders) } else { @("skills") }
		$exclude = if ($entry.Exclude) { @($entry.Exclude) } else { @() }
		$destination = Join-Path $config.Root $name
		$manifestPath = Join-Path $destination "UPSTREAM.md"

		if ($repository -notmatch '^[\w.-]+/[\w.-]+$') {
			Write-LogError "Source [$name] needs Repository in owner/name form => [$repository]"
			$failures++
			continue
		}

		Write-LogStep "[$name] $repository @ $ref => $destination"

		$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-skills-$name"
		$zipPath = Join-Path $tempRoot "skills.zip"
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
					Write-LogWarning "[$name] Behind upstream: vendored $($previous.Commit.Substring(0, 7)), head $($sha.Substring(0, 7)) - run Update-AiSkills -Source $name"
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

			# Collect every skill folder under the configured upstream folders, flattened by name.
			$incoming = @{}
			foreach ($folder in $folders) {
				$folderPath = Join-Path $sourceRoot.FullName ($folder -replace '/', '\')
				if (-not (Test-Path -Path $folderPath)) {
					Write-LogWarning "[$name] Upstream folder not found - skipped => [$folder]"
					continue
				}

				foreach ($skillDir in Get-ChildItem -Path $folderPath -Directory) {
					if (-not (Test-Path -Path (Join-Path $skillDir.FullName "SKILL.md"))) {
						continue
					}
					if ($exclude -contains $skillDir.Name) {
						Write-LogStep "[$name] Excluded => $($skillDir.Name)"
						continue
					}
					if ($incoming.ContainsKey($skillDir.Name)) {
						Write-LogWarning "[$name] Duplicate skill name across upstream folders - keeping the first => [$($skillDir.Name)]"
						continue
					}
					$incoming[$skillDir.Name] = @{ Source = $skillDir.FullName; Folder = $folder }
				}
			}

			if ($incoming.Count -eq 0) {
				Write-LogError "[$name] No skills found under [$($folders -join ', ')] - vendored copy left untouched!"
				$failures++
				continue
			}

			New-Item -ItemType Directory -Path $destination -Force | Out-Null

			# Remove only what the previous manifest says we vendored (plus incoming names, which
			# are about to be overwritten anyway). Anything else in the folder is never touched.
			foreach ($skill in (@($previous.Skills) + @($incoming.Keys) | Sort-Object -Unique)) {
				$existing = Join-Path $destination $skill
				if (Test-Path -Path $existing) {
					Remove-Item -Path $existing -Recurse -Force
				}
			}

			$rows = @()
			foreach ($skill in ($incoming.Keys | Sort-Object)) {
				$item = $incoming[$skill]
				Copy-Item -Path $item.Source -Destination (Join-Path $destination $skill) -Recurse -Force
				$description = Get-AiSkillDescription -SkillFile (Join-Path $item.Source "SKILL.md")
				$rows += "| ``$skill`` | ``$($item.Folder)`` | $description |"
			}

			$licenseName = "LICENSE.$($repository -replace '/', '-').txt"
			$upstreamLicense = Get-ChildItem -Path $sourceRoot.FullName -File -Filter "LICENSE*" | Select-Object -First 1
			if ($upstreamLicense) {
				Copy-Item -Path $upstreamLicense.FullName -Destination (Join-Path $destination $licenseName) -Force
			}

			$excludedText = if ($exclude.Count -gt 0) { ($exclude | ForEach-Object { "``$_``" }) -join ", " } else { "none" }
			$foldersText = ($folders | ForEach-Object { "``$_``" }) -join ", "
			$manifest = @(
				"# Vendored AI skills: $name",
				"",
				"Generated by ``Update-AiSkills`` - do not edit by hand, re-run ``Update-AiSkills -Source $name`` to refresh. Deployed into every AI harness by ``Deploy-AiSkills``.",
				"",
				"- **Source:** https://github.com/$repository",
				"- **Commit:** ``$sha`` (ref ``$ref``)",
				"- **Fetched:** $((Get-Date).ToString('s'))",
				"- **Upstream folders:** $foldersText",
				"- **Excluded:** $excludedText",
				"- **License:** ``$licenseName`` (upstream LICENSE, verbatim)",
				"",
				"| Skill | Upstream folder | Description |",
				"| ----- | --------------- | ----------- |"
			) + $rows

			Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8

			$removed = @($previous.Skills | Where-Object { -not $incoming.ContainsKey($_) })
			if ($removed.Count -gt 0) {
				Write-LogWarning "[$name] Removed skills no longer vendored => [$($removed -join ', ')]"
			}

			Write-LogSuccess "[$name] Vendored $($incoming.Count) skills from [$repository@$($sha.Substring(0, 7))]"
		}
		catch {
			Write-LogError "[$name] Updating AI skills failed => $($_.Exception.Message)"
			$failures++
		}
		finally {
			if (Test-Path -Path $tempRoot) {
				Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}

	if ($failures -eq 0 -and -not $Check) {
		Write-LogSuccess "AI skills vendored - run Deploy-AiSkills (or Bootstrap) to link them into the harnesses!"
	}
	elseif ($failures -gt 0) {
		Write-LogError "AI skills update finished with $failures failure(s)!"
	}
}

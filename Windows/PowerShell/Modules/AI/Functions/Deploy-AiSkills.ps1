function Deploy-AiSkills {
	<#
	.SYNOPSIS
		Links every skill under the skills root into each AI harness's user-level skills directory, on Windows and in WSL.

	.DESCRIPTION
		Agent Skills are discovered per harness from one flat user-level directory of
		<skill>/SKILL.md: ~/.claude/skills for Claude Code, ~/.agents/skills for Codex CLI and
		Gemini CLI. WinuX keeps the skills themselves in the repository under AiSkills.Root
		(default AI/Skills), one subfolder per source (vendored upstreams filled by
		Update-AiSkills, plus hand-written ones), so every machine running the repository sees
		the same skills in every project without any per-project setup. This function makes
		that link: for every <Root>\<source>\<skill>\SKILL.md it creates a symbolic link
		<harness>\<skill> -> that folder, in every directory listed in AiSkills.Harnesses.

		Per harness directory:
		- A symbolic link sitting at the harness path itself that points inside the repository
		  (the earlier whole-directory linking style) is replaced by a real directory, so the
		  harness folder stays machine-local and only individual skills are linked in.
		- Skill links are created through New-WindowsSymbolicLink, which backs up a real folder
		  of the same name before replacing it and self-heals an existing link.
		- Dangling links that point into the skills root but whose target is gone (a skill you
		  deleted or an excluded upstream skill) are removed. Links to anything else are never
		  touched, so skills installed by other tools coexist.
		- Inside WSL the same is done for every AiSkills.WSLHarnesses path
		  (/home/<DefaultWSLUsername>/...), pointing at the /mnt/<drive> mount of the repository,
		  in one `wsl -e sh <script>` invocation per harness directory. Skipped when no WSL
		  distribution or username is configured.

		The same skill name under two sources is reported and the first (sources sorted by name)
		wins. Requires administrator privileges (Test-AdminPrivileges, like SymbolicLinkMaker). Called
		by Bootstrap when the opt-in BootstrapConfig.Steps.AiSkills toggle is enabled (OFF by
		default: the base ships no skills, and machine-global agent tooling is never imposed by
		a vanilla bootstrap). Idempotent - re-runs self-heal.

	.EXAMPLE
		Deploy-AiSkills
		Links every skill under AI/Skills into ~/.claude/skills and ~/.agents/skills, and their WSL twins.
	#>
	[CmdletBinding()]
	param()

	Test-AdminPrivileges

	Write-LogTitle "Deploying AI Skills"

	$config = Resolve-AiSkillsConfig
	$root = $config.Root

	if (-not (Test-Path -Path $root)) {
		Write-LogWarning "Skills root [$root] does not exist - nothing to deploy (configure AiSkills.Sources and run Update-AiSkills, or add skills under it)!"
		return
	}

	# Every <source>\<skill>\SKILL.md, flattened by skill name; first source (by name) wins.
	# Shared with List-Skills so what is listed is exactly what is deployed.
	$roster = Get-AiSkillRoster -Root $root
	$skills = $roster.Skills
	foreach ($duplicate in $roster.Duplicates) {
		Write-LogWarning "Duplicate skill [$($duplicate.Name)] in source [$($duplicate.Source)] - keeping the one from [$($duplicate.KeptFrom)]"
	}

	if ($skills.Count -eq 0) {
		Write-LogWarning "No skills found under [$root] - nothing to deploy!"
		return
	}

	Write-LogStep "Skills root : $root ($($skills.Count) skills)"

	$repoRoot = (Get-RepositoryPath).Repo

	foreach ($harness in $config.Harnesses) {
		Write-LogStep "[$harness]"

		$existing = Get-Item -Path $harness -Force -ErrorAction SilentlyContinue
		if ($existing -and $existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
			$target = [string]$existing.LinkTarget
			if (-not $target) { $target = [string](@($existing.Target)[0]) }
			if ($target -and $target.TrimEnd('\').StartsWith($repoRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
				# Whole-directory link into the repository from an earlier setup: a link carries no
				# content, so replace it with a real directory and link skills individually below.
				$existing.Delete()
				$existing = $null
				Write-LogStep "Replaced directory link into the repository with a real directory"
			}
			else {
				Write-LogWarning "Skipped harness [$harness] - it is a link to [$target], not a directory WinuX manages"
				continue
			}
		}
		elseif ($existing -and -not $existing.PSIsContainer) {
			Write-LogWarning "Skipped harness [$harness] - a file sits at that path"
			continue
		}

		if (-not $existing) {
			New-Item -ItemType Directory -Path $harness -Force | Out-Null
		}

		foreach ($name in $skills.Keys) {
			New-WindowsSymbolicLink -Path (Join-Path $harness $name) -Target $skills[$name].Path -DisplayName "AiSkills.$name"
		}

		# Prune dangling links that point into the skills root (removed or excluded skills).
		foreach ($child in Get-ChildItem -Path $harness -Force -ErrorAction SilentlyContinue) {
			if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
			$target = [string]$child.LinkTarget
			if (-not $target) { $target = [string](@($child.Target)[0]) }
			if ($target -and $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -Path $target)) {
				$child.Delete()
				Write-LogStep "Removed dangling link => [$($child.Name)]"
			}
		}
	}

	if ($config.WSLHarnesses.Count -gt 0) {
		if (-not (Test-WSLDistributionInstalled)) {
			Write-LogWarning "WSL distribution not installed - skipping the WSL skill links!"
		}
		else {
			$distro = $Configuration.DefaultWSLDistribution
			$wslUser = $Configuration.DefaultWSLUsername

			# C:\Users\... -> /mnt/c/Users/... for the repository, applied to every skill path.
			$driveLetter = $repoRoot.Substring(0, 1).ToLower()
			$wslRepoRoot = "/mnt/$driveLetter" + $repoRoot.Substring(2).Replace('\', '/')
			$wslSkillsRoot = "/mnt/$driveLetter" + $root.Substring(2).Replace('\', '/')

			foreach ($harness in $config.WSLHarnesses) {
				Write-LogStep "[$harness] (WSL)"

				# One script per harness: replace a directory link into the repo with a real
				# directory, link every skill, then prune dangling links into the skills root.
				# The script goes through a file and `wsl -e sh <file>`: without -e, wsl.exe hands
				# the joined arguments to the user's login shell, which splits an inline `sh -c`
				# script at its first `;` and runs the rest with none of its variables set.
				$lines = @(
					"set -e",
					"h='$harness'",
					"if [ -L `"`$h`" ]; then case `"`$(readlink `"`$h`")`" in '$wslRepoRoot'*) rm `"`$h`";; esac; fi",
					"mkdir -p `"`$h`""
				)
				foreach ($name in $skills.Keys) {
					$wslSkillPath = "/mnt/$driveLetter" + $skills[$name].Path.Substring(2).Replace('\', '/')
					$lines += "ln -sfn '$wslSkillPath' `"`$h/$name`""
				}
				$lines += "for l in `"`$h`"/*; do [ -L `"`$l`" ] || continue; case `"`$(readlink `"`$l`")`" in '$wslSkillsRoot'*) [ -e `"`$l`" ] || rm `"`$l`";; esac; done"

				$scriptPath = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-skills-$([IO.Path]::GetRandomFileName()).sh"
				$wslScriptPath = "/mnt/$driveLetter" + $scriptPath.Substring(2).Replace('\', '/')
				try {
					[IO.File]::WriteAllText($scriptPath, ($lines -join "`n") + "`n")
					wsl -d $distro -u $wslUser -e sh $wslScriptPath
					if ($LASTEXITCODE -eq 0) {
						Write-LogSuccess "Linked $($skills.Count) skills into WSL => [$harness]"
					}
					else {
						Write-LogError "Failed to link skills into WSL => [$harness]"
					}
				}
				finally {
					Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
				}
			}
		}
	}

	Write-LogSuccess "AI skills deployed!"
}

function Deploy-AiMods {
	<#
	.SYNOPSIS
		Links every Claude Code mod under the mods root into the mods harness directory and points Claude Code at it, on Windows and in WSL.

	.DESCRIPTION
		Claude Code mods are function-hook plugins (a folder holding .claude-plugin\plugin.json
		and a hooks module) that draw bands, panes and status entries and hook engine events.
		The engine loads them from the folders named in CLAUDE_CODE_PLUGIN_DIRS, which it reads
		from the process environment or from the `env` block of the user settings file
		~/.claude/settings.json - never from a project's settings. WinuX keeps the mods in the
		repository under AiMods.Root (default AI/Mods), one subfolder per source (vendored
		upstreams filled by Update-AiMods, plus hand-written ones), so every machine running the
		repository gets the same mods in every session without any per-project setup.

		This function makes that connection in two steps:

		1. Links: for every <Root>\<source>\<mod>\.claude-plugin\plugin.json it creates a
		   symbolic link <harness>\<mod> -> that folder in every directory listed in
		   AiMods.Harnesses (default ~\.claude\mods), with the same per-harness rules as
		   Deploy-AiSkills: a directory link into the repository at the harness path is replaced
		   by a real directory, links go through New-WindowsSymbolicLink (which backs up a real
		   folder of the same name and self-heals an existing link), dangling links into the
		   mods root are pruned, and links to anything else are never touched.
		2. Plugin list: the single key env.CLAUDE_CODE_PLUGIN_DIRS of ~\.claude\settings.json is
		   rewritten through Resolve-AiModsPluginDirs and Set-ClaudeSettingsEnv - the links of the
		   FIRST harness, then every entry the user added by hand; entries under that harness
		   that no longer have a mod are dropped. Every other key of the settings file is kept.

		Inside WSL the same is done for every AiMods.WSLHarnesses path, pointing at the
		/mnt/<drive> mount of the repository, in one `wsl -e sh <script>` invocation per harness
		directory, and the WSL user's settings file is updated from Windows through the
		\\wsl.localhost\<distro> share with ':' as the separator. Skipped when no WSL
		distribution or username is configured; the settings update is skipped with a warning
		when the share is unreachable.

		Finally Test-AiModsCli checks that the Claude Code CLI is on PATH and accepts every mod
		(`claude plugin validate`). Its result only produces a warning: links and settings are
		always deployed, so installing or updating the CLI later is enough.

		The same mod name under two sources is reported and the first (sources sorted by name)
		wins. Requires administrator privileges (Test-AdminPrivileges, like SymbolicLinkMaker).
		Called by Bootstrap when the opt-in BootstrapConfig.Steps.AiMods toggle is enabled (OFF by
		default: the base ships no mods, and machine-global agent tooling is never imposed by a
		vanilla bootstrap). Idempotent - re-runs self-heal.

	.EXAMPLE
		Deploy-AiMods
		Links every mod under AI/Mods into ~/.claude/mods, its WSL twin, and lists them in CLAUDE_CODE_PLUGIN_DIRS.
	#>
	[CmdletBinding()]
	param()

	Test-AdminPrivileges

	Write-LogTitle "Deploying AI Mods"

	$config = Resolve-AiModsConfig
	$root = $config.Root

	if (-not (Test-Path -Path $root)) {
		Write-LogWarning "Mods root [$root] does not exist - nothing to deploy (configure AiMods.Sources and run Update-AiMods, or add mods under it)!"
		return
	}

	# Every <source>\<mod>\.claude-plugin\plugin.json, flattened by mod name; first source (by name) wins.
	$roster = Get-AiModRoster -Root $root
	$mods = $roster.Mods
	foreach ($duplicate in $roster.Duplicates) {
		Write-LogWarning "Duplicate mod [$($duplicate.Name)] in source [$($duplicate.Source)] - keeping the one from [$($duplicate.KeptFrom)]"
	}

	if ($mods.Count -eq 0) {
		Write-LogWarning "No mods found under [$root] - nothing to deploy!"
		return
	}

	Write-LogStep "Mods root : $root ($($mods.Count) mods)"

	$repoRoot = (Get-RepositoryPath).Repo

	# The first harness that could be linked is the one Claude Code is pointed at; the others
	# only receive links, so no mod is ever listed twice in CLAUDE_CODE_PLUGIN_DIRS.
	$settingsTargets = @()

	foreach ($harness in $config.Harnesses) {
		Write-LogStep "[$harness]"

		$existing = Get-Item -Path $harness -Force -ErrorAction SilentlyContinue
		if ($existing -and $existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
			$target = [string]$existing.LinkTarget
			if (-not $target) { $target = [string](@($existing.Target)[0]) }
			if ($target -and $target.TrimEnd('\').StartsWith($repoRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
				# Whole-directory link into the repository from an earlier setup: a link carries no
				# content, so replace it with a real directory and link mods individually below.
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

		$links = @()
		foreach ($name in $mods.Keys) {
			$link = Join-Path $harness $name
			New-WindowsSymbolicLink -Path $link -Target $mods[$name].Path -DisplayName "AiMods.$name"
			$links += $link
		}

		# Prune dangling links that point into the mods root (removed or excluded mods).
		foreach ($child in Get-ChildItem -Path $harness -Force -ErrorAction SilentlyContinue) {
			if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
			$target = [string]$child.LinkTarget
			if (-not $target) { $target = [string](@($child.Target)[0]) }
			if ($target -and $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -Path $target)) {
				$child.Delete()
				Write-LogStep "Removed dangling link => [$($child.Name)]"
			}
		}

		if ($settingsTargets.Count -eq 0) {
			$settingsTargets += @{ Label = "Windows"; Path = $config.SettingsPath; Harness = $harness; Links = $links; Separator = [char]';' }
		}
	}

	$windowsLinks = if ($settingsTargets.Count -gt 0) { @($settingsTargets[0].Links) } else { @() }

	if ($config.WSLHarnesses.Count -gt 0) {
		if (-not (Test-WSLDistributionInstalled)) {
			Write-LogWarning "WSL distribution not installed - skipping the WSL mod links!"
		}
		else {
			$distro = Get-ConfigSetting -Path 'DefaultWSLDistribution'
			$wslUser = Get-ConfigSetting -Path 'DefaultWSLUsername'

			# C:\Users\... -> /mnt/c/Users/... for the repository, applied to every mod path.
			$driveLetter = $repoRoot.Substring(0, 1).ToLower()
			$wslRepoRoot = "/mnt/$driveLetter" + $repoRoot.Substring(2).Replace('\', '/')
			$wslModsRoot = "/mnt/$driveLetter" + $root.Substring(2).Replace('\', '/')
			$wslLinked = $false

			foreach ($harness in $config.WSLHarnesses) {
				Write-LogStep "[$harness] (WSL)"

				# One script per harness: replace a directory link into the repo with a real
				# directory, link every mod, then prune dangling links into the mods root.
				# The script goes through a file and `wsl -e sh <file>`: without -e, wsl.exe hands
				# the joined arguments to the user's login shell, which splits an inline `sh -c`
				# script at its first `;` and runs the rest with none of its variables set.
				$lines = @(
					"set -e",
					"h='$harness'",
					"if [ -L `"`$h`" ]; then case `"`$(readlink `"`$h`")`" in '$wslRepoRoot'*) rm `"`$h`";; esac; fi",
					"mkdir -p `"`$h`""
				)
				foreach ($name in $mods.Keys) {
					$wslModPath = "/mnt/$driveLetter" + $mods[$name].Path.Substring(2).Replace('\', '/')
					$lines += "ln -sfn '$wslModPath' `"`$h/$name`""
				}
				$lines += "for l in `"`$h`"/*; do [ -L `"`$l`" ] || continue; case `"`$(readlink `"`$l`")`" in '$wslModsRoot'*) [ -e `"`$l`" ] || rm `"`$l`";; esac; done"

				$scriptPath = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-mods-$([IO.Path]::GetRandomFileName()).sh"
				$wslScriptPath = "/mnt/$driveLetter" + $scriptPath.Substring(2).Replace('\', '/')
				try {
					[IO.File]::WriteAllText($scriptPath, ($lines -join "`n") + "`n")
					wsl -d $distro -u $wslUser -e sh $wslScriptPath
					if ($LASTEXITCODE -eq 0) {
						Write-LogSuccess "Linked $($mods.Count) mods into WSL => [$harness]"
						if (-not $wslLinked) {
							$wslLinked = $true
							$wslLinks = @($mods.Keys | ForEach-Object { "$harness/$_" })
							$shareHome = "\\wsl.localhost\$distro\home\$wslUser"
							if (Test-Path -LiteralPath $shareHome) {
								$settingsTargets += @{ Label = "WSL"; Path = "\\wsl.localhost\$distro" + $config.WSLSettingsPath.Replace('/', '\'); Harness = $harness; Links = $wslLinks; Separator = [char]':' }
							}
							else {
								Write-LogWarning "WSL share [$shareHome] is not reachable - the WSL Claude Code settings were not updated!"
							}
						}
					}
					else {
						Write-LogError "Failed to link mods into WSL => [$harness]"
					}
				}
				finally {
					Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
				}
			}
		}
	}

	# Point Claude Code at the linked mods through the one settings key it reads them from.
	foreach ($settings in $settingsTargets) {
		$current = ""
		if (Test-Path -LiteralPath $settings.Path) {
			try {
				$document = Get-Content -LiteralPath $settings.Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
				if ($document.env -and $document.env.PSObject.Properties['CLAUDE_CODE_PLUGIN_DIRS']) {
					$current = [string]$document.env.CLAUDE_CODE_PLUGIN_DIRS
				}
			}
			catch {
				# Set-ClaudeSettingsEnv reports an unparseable file and leaves it untouched.
				Write-LogDebug "Could not read env.CLAUDE_CODE_PLUGIN_DIRS from [$($settings.Path)] => $($_.Exception.Message)"
			}
		}

		$value = Resolve-AiModsPluginDirs -Existing $current -Deployed $settings.Links -Harness $settings.Harness -Separator $settings.Separator
		if (Set-ClaudeSettingsEnv -Name 'CLAUDE_CODE_PLUGIN_DIRS' -Value $value -SettingsPath $settings.Path) {
			Write-LogSuccess "Claude Code plugin list updated ($($settings.Label)) => [$($settings.Path)]"
		}
	}

	$cli = Test-AiModsCli -ModPath $windowsLinks
	if (-not $cli.Installed) {
		Write-LogWarning "Claude Code CLI (claude) not found on PATH - mods are deployed but cannot be used until the Claude Code CLI is installed or updated!"
	}
	elseif ($cli.Invalid.Count -gt 0) {
		$invalidNames = @($cli.Invalid | ForEach-Object { Split-Path -Path $_ -Leaf })
		Write-LogWarning "claude plugin validate failed for [$($invalidNames -join ', ')] - mods are deployed but cannot be used until the Claude Code CLI is updated or the mod is fixed!"
	}

	Write-LogSuccess "AI mods deployed!"
}

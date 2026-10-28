function Deploy-AiArtifacts {
	<#
	.SYNOPSIS
		Links the repository's AI skills, mods, rules, prompts and agents into the AI apps this machine deploys into, on Windows and in WSL.

	.DESCRIPTION
		The apps are the AiHarnesses entries AiArtifacts.Deploy names for this machine type (the
		base catalogue: claude-code, codex, gemini-cli, copilot, all inactive until named); the
		items are every <Root>\<Kind>\<source>\<item> of the sources read (own first, then winux,
		example and the vendored sources in name order; the first wins an item name two carry,
		with a warning), minus the AiArtifacts.Exclude entries. Get-AiArtifactPlan joins the two;
		this function carries the plan out. Design: docs/winux/ai/artifacts.md.

		Per destination of an app:

		- Each: one symbolic link per item in the folder - the item folder itself, or the first
		  file of the destination's Files the item has, named <item> plus that file's extension.
		- Copy: as Each, copied instead of linked; a copy that differs from the repository's is
		  replaced.
		- File: one link to the item AiArtifacts.Use names for the kind (the rules linked as
		  ~\.claude\CLAUDE.md, ~\.codex\AGENTS.md, ...).

		A destination two apps name is filled once; one no item goes to is never created (only
		pruned). A folder destination that is itself a link into the repository (the earlier
		whole-folder style) is replaced by a real folder; one that links elsewhere, or a file in
		its place, is skipped. Links go through New-WindowsSymbolicLink, which first copies a real
		file or folder in the way into Backups\Windows\SymbolicLinks\AiArtifacts.<kind>.<item>
		and skips the item when that copy fails; a link in the way (a wrong one, or one whose
		target is gone) holds no content and is simply replaced. Only dangling links that point into the
		artifacts root are pruned; a link to anything else is never touched.

		Hooks of a destination:

		- claude-plugin-dirs: env.CLAUDE_CODE_PLUGIN_DIRS of ~\.claude\settings.json lists the
		  links (';'-separated), then every entry added by hand (Resolve-AiModsPluginDirs and
		  Set-ClaudeSettingsEnv, every other setting kept), and Test-AiModsCli runs
		  `claude plugin validate` on each; a missing or rejecting CLI only warns.
		- managed-settings: the WSL twin is made as root (/etc/claude-code is root-owned). The
		  Windows link needs the administrator rights this function asks for anyway.

		WSL: a harness with WSL = $true deploys every destination that has a WSL twin (a {User}
		path mapped onto /home/<DefaultWSLUsername>, or the destination's WSLPath) inside the
		default WSL distribution too, pointing at the /mnt/<drive> mount of the repository, in
		one `wsl -e sh <script>` call per destination, with the same backup, replace and prune
		rules (a real item is copied into the same Backups folder through its /mnt path). The
		claude-plugin-dirs hook updates the WSL user's settings file through the
		\\wsl.localhost\<distro> share with ':' as the separator. Skipped when no WSL
		distribution or username is configured.

		Requires administrator privileges (Test-AdminPrivileges, like SymbolicLinkMaker) unless
		-WhatIf is given. Called by Bootstrap when the opt-in BootstrapConfig.Steps.AiArtifacts
		toggle is enabled (OFF by default). Idempotent - re-runs self-heal.

	.PARAMETER Kind
		Deploys only these kinds: Skills, Mods, Rules, Prompts, Agents. Defaults to every kind.

	.EXAMPLE
		Deploy-AiArtifacts
		Links every artifact into every destination of the harnesses this machine deploys into, and their WSL twins.

	.EXAMPLE
		Deploy-AiArtifacts -Kind Rules -WhatIf
		Reports which rules links are missing or wrong, changing nothing.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Position = 0)]
		[ValidateSet('Skills', 'Mods', 'Rules', 'Prompts', 'Agents')]
		[string[]]$Kind
	)

	$whatIf = [bool]$WhatIfPreference
	if (-not $whatIf) {
		Test-AdminPrivileges
	}

	Write-LogTitle "Deploying AI Artifacts"

	$config = Resolve-AiArtifactsConfig

	if ($config.Deploy.Count -eq 0) {
		Write-LogWarning "No harness to deploy into - set AiArtifacts.Deploy for this machine type (the catalogue is AiHarnesses)!"
		return
	}

	$root = $config.Root.TrimEnd('\')
	$repoRoot = (Get-RepositoryPath).Repo.TrimEnd('\')
	Write-LogStep "Artifacts root : $root"
	Write-LogStep "Harnesses      : $($config.Deploy -join ', ')"

	$planParams = @{ Config = $config }
	if ($Kind) { $planParams.Kind = $Kind }
	$plan = Get-AiArtifactPlan @planParams
	foreach ($message in $plan.Warnings) { Write-LogWarning $message }
	foreach ($message in $plan.Notes) { Write-LogStep $message }

	$failures = 0
	$deployed = 0

	# C:\Users\... -> /mnt/c/Users/... for paths inside the repository.
	$toWsl = {
		param([string]$path)
		"/mnt/" + $path.Substring(0, 1).ToLowerInvariant() + $path.Substring(2).Replace('\', '/')
	}
	# A value safe inside single quotes in sh.
	$quote = {
		param([string]$value)
		"'" + $value.Replace("'", "'\''") + "'"
	}
	$linkTarget = {
		param($item)
		$target = [string]$item.LinkTarget
		if (-not $target) { $target = [string](@($item.Target)[0]) }
		$target
	}
	$sameContent = {
		param([string]$source, [string]$target)
		$sourceItem = Get-Item -LiteralPath $source -Force
		if (-not $sourceItem.PSIsContainer) {
			return (Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash
		}
		$left = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($source.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash } | Sort-Object)
		$right = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($target.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash } | Sort-Object)
		return ($left -join "`n") -eq ($right -join "`n")
	}

	$wsl = $null
	$wslChecked = $false

	foreach ($destination in $plan.Destinations) {
		$path = $destination.Path
		$isFolder = $destination.Placement -ne 'file'
		$hooks = @($destination.Hooks)

		if ($destination.Items.Count -gt 0) {
			Write-LogStep "[$($destination.Harness)] $($destination.Kind) => $path"
		}

		# --- Windows ---------------------------------------------------------------------------
		$ready = $destination.Items.Count -gt 0
		if ($ready -and $isFolder) {
			$existing = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
			if ($existing -and $existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
				$target = & $linkTarget $existing
				if ($target -and $target.TrimEnd('\').StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
					if ($whatIf) {
						Write-LogStep "WRONG   $path is a folder link into the repository (will be replaced)"
						$failures++
						$ready = $false
					}
					else {
						$existing.Delete()
						Write-LogStep "Replaced folder link into the repository with a real folder"
					}
				}
				else {
					Write-LogWarning "Skipped [$path] - it is a link to [$target], not a folder WinuX manages"
					$failures++
					$ready = $false
				}
			}
			elseif ($existing -and -not $existing.PSIsContainer) {
				Write-LogWarning "Skipped [$path] - a file sits at that path"
				$failures++
				$ready = $false
			}
			if ($ready -and -not $whatIf -and -not (Test-Path -LiteralPath $path)) {
				New-Item -ItemType Directory -Path $path -Force | Out-Null
			}
		}

		$links = @()
		if ($ready) {
			foreach ($item in $destination.Items) {
				$key = "AiArtifacts.$($item.Kind).$($item.Name)"
				if (-not $isFolder) { $key += "." + (Split-Path -Path $item.Target -Leaf) }
				$current = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
				$isLink = $current -and ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)

				if ($destination.Placement -eq 'copy') {
					if ($current -and -not $isLink -and (& $sameContent $item.Source $item.Target)) {
						$deployed++
						$links += $item.Target
						continue
					}
					if ($whatIf) {
						Write-LogStep "$(if ($current) { 'DIFFERS' } else { 'MISSING' }) $($item.Target)"
						$failures++
						continue
					}
					try {
						if ($current -and -not $isLink) {
							$backupDir = Backup-RepositoryItem -Path $item.Target -Category "SymbolicLinks" -Key $key
							Write-LogWarning "Backed up existing item => [$($item.Target)] => [$backupDir]"
						}
						if ($current) {
							if ($isLink -or -not $current.PSIsContainer) { Remove-Item -LiteralPath $item.Target -Force } else { Remove-Item -LiteralPath $item.Target -Recurse -Force }
						}
						Copy-Item -LiteralPath $item.Source -Destination $item.Target -Recurse -Force
						Write-LogStep "copied  $($item.Target)"
						$deployed++
						$links += $item.Target
					}
					catch {
						Write-LogError "Skipped [$($item.Target)] => $($_.Exception.Message)"
						$failures++
					}
					continue
				}

				if ($isLink -and (& $linkTarget $current).TrimEnd('\') -eq $item.Source.TrimEnd('\')) {
					$deployed++
					$links += $item.Target
					continue
				}
				if ($whatIf) {
					Write-LogStep "$(if ($current) { 'WRONG  ' } else { 'MISSING' }) $($item.Target)"
					$failures++
					continue
				}
				# A link in the way (wrong, or dangling after its target moved) is removed here: it
				# holds no content, and New-WindowsSymbolicLink tests the path with Test-Path, which
				# is false for a dangling link, so it would leave it and then fail to create its own.
				if ($isLink) {
					$current.Delete()
				}
				New-WindowsSymbolicLink -Path $item.Target -Target $item.Source -DisplayName $key
				$created = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
				if ($created -and ($created.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (& $linkTarget $created).TrimEnd('\') -eq $item.Source.TrimEnd('\')) {
					$deployed++
					$links += $item.Target
				}
				else {
					$failures++
				}
			}
		}

		# Prune dangling links into the artifacts root. The separator check keeps a sibling
		# folder such as "<root>Backup" out of the prune.
		if ($isFolder -and (Test-Path -LiteralPath $path -PathType Container)) {
			foreach ($child in Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue) {
				if (-not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
				$target = & $linkTarget $child
				if (-not $target -or -not $target.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $target)) { continue }
				if ($whatIf) {
					Write-LogStep "STALE   $($child.FullName) (dangling link into the artifacts root)"
					$failures++
				}
				else {
					$child.Delete()
					Write-LogStep "Removed dangling link => [$($child.Name)]"
				}
			}
		}

		if ($ready -and $hooks -contains 'claude-plugin-dirs' -and $links.Count -gt 0) {
			$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
			$current = ""
			if (Test-Path -LiteralPath $settingsPath) {
				try {
					$document = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
					if ($document.env -and $document.env.PSObject.Properties['CLAUDE_CODE_PLUGIN_DIRS']) {
						$current = [string]$document.env.CLAUDE_CODE_PLUGIN_DIRS
					}
				}
				catch {
					# Set-ClaudeSettingsEnv reports an unparseable file and leaves it untouched.
					Write-LogDebug "Could not read env.CLAUDE_CODE_PLUGIN_DIRS from [$settingsPath] => $($_.Exception.Message)"
				}
			}
			$value = Resolve-AiModsPluginDirs -Existing $current -Deployed $links -Harness $path -Separator ';'
			if (-not (Set-ClaudeSettingsEnv -Name 'CLAUDE_CODE_PLUGIN_DIRS' -Value $value -SettingsPath $settingsPath -WhatIf:$whatIf)) {
				$failures++
			}
			if (-not $whatIf) {
				$cli = Test-AiModsCli -ModPath $links
				if (-not $cli.Installed) {
					Write-LogWarning "Claude Code CLI (claude) not found on PATH - mods are deployed but cannot be used until the Claude Code CLI is installed or updated!"
				}
				elseif ($cli.Invalid.Count -gt 0) {
					$invalidNames = @($cli.Invalid | ForEach-Object { Split-Path -Path $_ -Leaf })
					Write-LogWarning "claude plugin validate failed for [$($invalidNames -join ', ')] - mods are deployed but cannot be used until the Claude Code CLI is updated or the mod is fixed!"
				}
			}
		}

		# --- WSL twin --------------------------------------------------------------------------
		if (-not $destination.WSLPath -or $destination.Items.Count -eq 0) { continue }

		if (-not $wslChecked) {
			$wslChecked = $true
			if (Test-WSLDistributionInstalled) {
				$wsl = @{
					Distro = [string](Get-ConfigSetting -Path 'DefaultWSLDistribution')
					User   = $config.WSLUser
				}
			}
			else {
				Write-LogWarning "WSL distribution not installed - skipping the WSL artifact links!"
			}
		}
		if (-not $wsl) { continue }

		$wslPath = $destination.WSLPath.TrimEnd('/')
		if ($whatIf) {
			Write-LogStep "WSL     $wslPath => $($destination.Items.Count) item(s) would be deployed"
			continue
		}

		$asUser = if ($hooks -contains 'managed-settings') { 'root' } else { $wsl.User }
		$wslRoot = & $toWsl $root
		$wslBackup = (& $toWsl (Join-Path $repoRoot "Backups\Windows\SymbolicLinks")) + "/"
		$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

		# One script per destination. The script goes through a file and `wsl -e sh <file>`:
		# without -e, wsl.exe hands the joined arguments to the user's login shell, which splits
		# an inline `sh -c` script at its first `;` and runs the rest with none of its variables set.
		$lines = @("f=0", "d=$(& $quote $wslPath)")
		if ($isFolder) {
			$lines += "if [ -L `"`$d`" ]; then case `"`$(readlink `"`$d`")`" in $(& $quote (& $toWsl $repoRoot))*) rm `"`$d`";; esac; fi"
			$lines += "if [ -L `"`$d`" ] || { [ -e `"`$d`" ] && [ ! -d `"`$d`" ]; }; then echo `"SKIPPED `$d (not a folder WinuX manages)`" >&2; exit 1; fi"
			$lines += "mkdir -p `"`$d`" || exit 1"
		}
		else {
			$lines += "mkdir -p `"`$(dirname `"`$d`")`" || exit 1"
		}
		foreach ($item in $destination.Items) {
			$key = "AiArtifacts.$($item.Kind).$($item.Name)"
			if (-not $isFolder) { $key += "." + (Split-Path -Path $item.Target -Leaf) }
			$lines += "s=$(& $quote (& $toWsl $item.Source)); t=$(& $quote $item.WSLTarget); b=$(& $quote ($wslBackup + ($key -replace '[\\/:*?"<>|]', '_') + "/$stamp"))"
			if ($destination.Placement -eq 'copy') {
				$lines += "if [ -e `"`$t`" ] && [ ! -L `"`$t`" ] && diff -rq `"`$s`" `"`$t`" >/dev/null 2>&1; then :"
			}
			else {
				$lines += "if [ -L `"`$t`" ] && [ `"`$(readlink `"`$t`")`" = `"`$s`" ]; then :"
			}
			$lines += "elif [ -e `"`$t`" ] && [ ! -L `"`$t`" ] && ! { mkdir -p `"`$b`" && cp -a `"`$t`" `"`$b/`"; }; then echo `"SKIPPED `$t (its backup failed, left untouched)`" >&2; f=1"
			$lines += "else"
			$lines += "  if [ -e `"`$t`" ] || [ -L `"`$t`" ]; then rm -rf `"`$t`"; fi"
			if ($destination.Placement -eq 'copy') {
				$lines += "  cp -a `"`$s`" `"`$t`" || f=1"
			}
			else {
				$lines += "  ln -sfn `"`$s`" `"`$t`" || f=1"
			}
			$lines += "fi"
		}
		if ($isFolder) {
			$lines += "for l in `"`$d`"/* `"`$d`"/.[!.]*; do [ -L `"`$l`" ] && [ ! -e `"`$l`" ] || continue; case `"`$(readlink `"`$l`")`" in $(& $quote $wslRoot)/*) rm `"`$l`";; esac; done"
		}
		$lines += 'exit $f'

		$scriptPath = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-artifacts-$([IO.Path]::GetRandomFileName()).sh"
		try {
			[IO.File]::WriteAllText($scriptPath, ($lines -join "`n") + "`n")
			wsl -d $wsl.Distro -u $asUser -e sh (& $toWsl $scriptPath)
			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess "Deployed $($destination.Items.Count) item(s) into WSL => [$wslPath]"
				$deployed += $destination.Items.Count
			}
			else {
				Write-LogError "Failed to deploy into WSL => [$wslPath]"
				$failures++
				continue
			}
		}
		finally {
			Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
		}

		if ($hooks -contains 'claude-plugin-dirs') {
			$shareHome = "\\wsl.localhost\$($wsl.Distro)\home\$($wsl.User)"
			if (-not (Test-Path -LiteralPath $shareHome)) {
				Write-LogWarning "WSL share [$shareHome] is not reachable - the WSL Claude Code settings were not updated!"
				continue
			}
			$settingsPath = "$shareHome\.claude\settings.json"
			$current = ""
			if (Test-Path -LiteralPath $settingsPath) {
				try {
					$document = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
					if ($document.env -and $document.env.PSObject.Properties['CLAUDE_CODE_PLUGIN_DIRS']) {
						$current = [string]$document.env.CLAUDE_CODE_PLUGIN_DIRS
					}
				}
				catch {
					Write-LogDebug "Could not read env.CLAUDE_CODE_PLUGIN_DIRS from [$settingsPath] => $($_.Exception.Message)"
				}
			}
			$wslLinks = @($destination.Items | ForEach-Object { $_.WSLTarget })
			$value = Resolve-AiModsPluginDirs -Existing $current -Deployed $wslLinks -Harness $wslPath -Separator ':'
			if (-not (Set-ClaudeSettingsEnv -Name 'CLAUDE_CODE_PLUGIN_DIRS' -Value $value -SettingsPath $settingsPath)) {
				$failures++
			}
		}
	}

	if ($whatIf) {
		if ($failures -eq 0) {
			Write-LogSuccess "AI artifacts fully deployed ($deployed items)!"
		}
		else {
			Write-LogWarning "AI artifacts incomplete: $failures item(s) need deployment!"
		}
		return
	}

	if ($failures -eq 0) {
		Write-LogSuccess "AI artifacts deployed ($deployed items)!"
	}
	else {
		Write-LogError "AI artifacts deployment finished with $failures failure(s)!"
	}
}

function Deploy-AiManagedSettings {
	<#
	.SYNOPSIS
		Deploys a rules item's managed settings as an administrator-owned copy, with its hooks, the ownership guard and ai-profile.conf, on Windows and in WSL.

	.DESCRIPTION
		The managed-settings destination of a harness (the one with the managed-settings hook:
		C:\Program Files\ClaudeCode\managed-settings.json, WSL /etc/claude-code/) is never a
		link: a link into the repository would let anything that can write the repository
		loosen the policy. Deploy-AiArtifacts hands that destination to this function, which
		writes a copy into the administrator-owned folder:

		  managed-settings.json    rendered by ConvertTo-AiManagedSettings ({ManagedDir}
		                           replaced, forceLoginOrgUUID from the AI profile's Plan, the
		                           ownership guard wired into UserPromptSubmit and PreToolUse)
		  hooks\                   the rules item's hooks folder, file by file (scripts with
		                           LF line endings)
		  ai-ownership-guard.sh    the engine's guard (AI\Hooks of the repository), profiles only
		  ai-profile.conf          the profile, Plan and ownership patterns, profiles only

		A file is rewritten only when its rendered content differs from the deployed one. A
		link in the way (the earlier link-style deploy) is replaced; a real file that differs
		is first backed up through Backup-RepositoryItem into
		Backups\Windows\SymbolicLinks\AiArtifacts.rules.<item>.<file>. Files the folder holds
		that this function did not render are left alone.

		WSL (WSLPath set and -Distribution given): the same files, rendered for the WSL folder,
		are staged in a temporary folder and copied in one `wsl -d <distro> -u root -e sh
		<script>` call (root:root, mode 644), each only when `cmp` finds it different; a real
		file that differs is copied into the same Backups folder through its /mnt path first.

		Returns @{ Deployed; Failures }. -WhatIf reports MISSING and DIFFERS files and changes
		nothing. The caller holds the administrator rights (Deploy-AiArtifacts asks for them).

	.PARAMETER Destination
		The plan destination (Get-AiArtifactPlan): Path, WSLPath and the one rules item whose
		managed-settings.json it takes.

	.PARAMETER AiProfile
		A resolved AI profile (Resolve-AiProfile).

	.PARAMETER Distribution
		The WSL distribution to deploy the twin into. Empty: no WSL twin.

	.PARAMETER GuardPath
		The ownership guard script. Defaults to AI\Hooks\ai-ownership-guard.sh of the repository, the file
		WinuX and Foundation ship as one mirror file.

	.PARAMETER BackupRepoRoot
		The repository whose Backups folder receives the WSL backups. Defaults to Get-RepositoryPath.

	.EXAMPLE
		Deploy-AiManagedSettings -Destination $destination -AiProfile (Resolve-AiProfile) -WhatIf
		Reports which managed files are missing or differ, changing nothing.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Destination,

		[Parameter()]
		[hashtable]$AiProfile,

		[Parameter()]
		[string]$Distribution,

		[Parameter()]
		[string]$GuardPath = (Join-Path (Get-RepositoryPath).Repo 'AI\Hooks\ai-ownership-guard.sh'),

		[Parameter()]
		[string]$BackupRepoRoot
	)

	$whatIf = [bool]$WhatIfPreference
	$result = @{ Deployed = 0; Failures = 0 }

	$item = @($Destination.Items)[0]
	if (-not $item) { return $result }
	$active = $AiProfile -and $AiProfile.Enabled
	$template = [IO.File]::ReadAllText($item.Source)
	$rulesDir = Split-Path -Parent $item.Source
	$settingsName = Split-Path -Leaf $Destination.Path
	$utf8 = [Text.UTF8Encoding]::new($false)

	# Relative name -> text, for one managed folder.
	$render = {
		param([string]$ManagedDir)
		$rendered = ConvertTo-AiManagedSettings -Template $template -ManagedDir $ManagedDir -AiProfile $AiProfile
		foreach ($problem in $rendered.Problems) { Write-LogWarning $problem }
		if (-not $rendered.Settings) { return $null }
		$files = [ordered]@{ $settingsName = $rendered.Settings }
		$hooksDir = Join-Path $rulesDir 'hooks'
		if (Test-Path -LiteralPath $hooksDir -PathType Container) {
			foreach ($file in (Get-ChildItem -LiteralPath $hooksDir -File -Recurse | Sort-Object FullName)) {
				$relative = 'hooks/' + $file.FullName.Substring($hooksDir.Length + 1).Replace('\', '/')
				$files[$relative] = ([IO.File]::ReadAllText($file.FullName)) -replace "`r`n", "`n"
			}
		}
		if ($active) {
			if (Test-Path -LiteralPath $GuardPath -PathType Leaf) {
				$files['ai-ownership-guard.sh'] = ([IO.File]::ReadAllText($GuardPath)) -replace "`r`n", "`n"
			}
			else {
				Write-LogWarning "The ownership guard is missing => [$GuardPath] - the managed settings call a script that is not deployed!"
			}
			$files['ai-profile.conf'] = $rendered.ProfileConf
		}
		return $files
	}

	# --- Windows ---------------------------------------------------------------------------
	$managedDir = Split-Path -Parent $Destination.Path
	$files = & $render $managedDir
	if ($null -eq $files) {
		$result.Failures++
		return $result
	}
	foreach ($relative in $files.Keys) {
		$target = Join-Path $managedDir ($relative.Replace('/', '\'))
		$content = [string]$files[$relative]
		$current = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
		$isLink = $current -and ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)
		if ($current -and -not $isLink -and -not $current.PSIsContainer -and [IO.File]::ReadAllText($target) -ceq $content) {
			$result.Deployed++
			continue
		}
		if ($whatIf) {
			Write-LogStep "$(if ($current -and -not $isLink) { 'DIFFERS' } elseif ($current) { 'WRONG  ' } else { 'MISSING' }) $target"
			$result.Failures++
			continue
		}
		try {
			if ($isLink) {
				$current.Delete()
			}
			elseif ($current) {
				$key = "AiArtifacts.rules.$($item.Name).$($relative.Replace('/', '.'))"
				$backupDir = Backup-RepositoryItem -Path $target -Category "SymbolicLinks" -Key $key
				Write-LogWarning "Backed up existing item => [$target] => [$backupDir]"
			}
			New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
			[IO.File]::WriteAllText($target, $content, $utf8)
			Write-LogStep "copied  $target"
			$result.Deployed++
		}
		catch {
			Write-LogError "Skipped [$target] => $($_.Exception.Message)" -Exception $_
			$result.Failures++
		}
	}

	# --- WSL twin --------------------------------------------------------------------------
	if (-not $Destination.WSLPath -or -not $Distribution) { return $result }
	if ($whatIf) {
		Write-LogStep "WSL     $($Destination.WSLPath) => the managed copy would be checked"
		return $result
	}

	$wslDir = $Destination.WSLPath.Substring(0, $Destination.WSLPath.LastIndexOf('/'))
	if (-not $wslDir) { $wslDir = '/' }
	$wslFiles = & $render $wslDir
	if ($null -eq $wslFiles) {
		$result.Failures++
		return $result
	}

	if (-not $BackupRepoRoot) { $BackupRepoRoot = (Get-RepositoryPath).Repo }
	$toWsl = {
		param([string]$path)
		"/mnt/" + $path.Substring(0, 1).ToLowerInvariant() + $path.Substring(2).Replace('\', '/')
	}
	$quote = {
		param([string]$value)
		"'" + $value.Replace("'", "'\''") + "'"
	}

	$stage = Join-Path ([IO.Path]::GetTempPath()) "winux-ai-managed-$([IO.Path]::GetRandomFileName())"
	$scriptPath = "$stage.sh"
	try {
		New-Item -ItemType Directory -Path $stage -Force | Out-Null
		$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
		$backupBase = (& $toWsl (Join-Path $BackupRepoRoot.TrimEnd('\') "Backups\Windows\SymbolicLinks")) + "/"
		$lines = @("f=0", "d=$(& $quote $wslDir)", "mkdir -p `"`$d`" || exit 1")
		$index = 0
		foreach ($relative in $wslFiles.Keys) {
			$index++
			$staged = Join-Path $stage "file$index"
			[IO.File]::WriteAllText($staged, [string]$wslFiles[$relative], $utf8)
			$key = ("AiArtifacts.rules.$($item.Name).$($relative.Replace('/', '.'))") -replace '[\\/:*?"<>|]', '_'
			$lines += "s=$(& $quote (& $toWsl $staged)); t=`"`$d/`"$(& $quote $relative); b=$(& $quote ($backupBase + $key + "/$stamp"))"
			$lines += "if [ -L `"`$t`" ]; then rm `"`$t`"; fi"
			$lines += "if [ -f `"`$t`" ] && cmp -s `"`$s`" `"`$t`"; then :"
			$lines += "elif [ -e `"`$t`" ] && ! { mkdir -p `"`$b`" && cp -a `"`$t`" `"`$b/`"; }; then echo `"SKIPPED `$t (its backup failed, left untouched)`" >&2; f=1"
			$lines += "else mkdir -p `"`$(dirname `"`$t`")`" && cp `"`$s`" `"`$t`" && chown root:root `"`$t`" && chmod 644 `"`$t`" || f=1; fi"
		}
		$lines += 'exit $f'
		[IO.File]::WriteAllText($scriptPath, ($lines -join "`n") + "`n")
		wsl -d $Distribution -u root -e sh (& $toWsl $scriptPath)
		if ($LASTEXITCODE -eq 0) {
			Write-LogSuccess "Deployed the managed settings copy into WSL => [$wslDir]"
			$result.Deployed += $wslFiles.Count
		}
		else {
			Write-LogError "Failed to deploy the managed settings copy into WSL => [$wslDir]"
			$result.Failures++
		}
	}
	finally {
		Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
	}

	return $result
}

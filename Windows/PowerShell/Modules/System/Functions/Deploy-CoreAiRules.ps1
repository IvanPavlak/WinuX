function Deploy-CoreAiRules {
	<#
	.SYNOPSIS
		Deploys the CoreAiRules enforcement layer into WSL (root-owned Claude Code managed settings).

	.DESCRIPTION
		Symlinks AI/Claude/managed-settings.json to /etc/claude-code/managed-settings.json inside
		the default WSL distribution, so Claude Code sessions running in WSL are governed by the
		same managed (admin-owned, highest-precedence) settings as Windows sessions.

		This is the one CoreAiRules link SymbolicLinkMaker cannot create: /etc is root-owned and the
		engine's WSL branch never elevates, while this function runs every wsl.exe call as root
		(`wsl -u root`, no sudo prompt needed). Every other CoreAiRules link - the per-harness
		instruction files on Windows and in WSL, and the Windows managed settings under
		C:\ProgramData\ClaudeCode - is a regular PathTemplates.SymbolicLinks entry handled by
		SymbolicLinkMaker. See docs/ai/coreairules.md for the full design.

		Does nothing when the configured WSL distribution is not installed, and never links to a
		missing target. Idempotent (`ln -sfn`) - reruns self-heal the link. Called by Bootstrap
		when the opt-in BootstrapConfig.Steps.CoreAiRules toggle is enabled (OFF by default:
		machine-global AI policy is never imposed by a vanilla bootstrap).

	.EXAMPLE
		Deploy-CoreAiRules
		Creates /etc/claude-code/managed-settings.json inside the default WSL distribution.
	#>

	Write-LogTitle "Deploying CoreAiRules"

	if (-not (Test-WSLDistributionInstalled)) {
		Write-LogWarning "WSL distribution not installed - skipping the WSL CoreAiRules enforcement layer!"
		return
	}

	$distro = $Configuration.DefaultWSLDistribution
	$repoRoot = (Get-RepositoryPath).Repo

	# Convert the Windows repo path to its WSL mount (C:\Users\... -> /mnt/c/Users/...).
	$driveLetter = $repoRoot.Substring(0, 1).ToLower()
	$wslTarget = "/mnt/$driveLetter" + $repoRoot.Substring(2).Replace('\', '/') + "/AI/Claude/managed-settings.json"
	$wslLinkDir = "/etc/claude-code"
	$wslLinkPath = "$wslLinkDir/managed-settings.json"

	wsl -d $distro -u root test -e $wslTarget
	if ($LASTEXITCODE -ne 0) {
		Write-LogWarning "Skipped WSL symlink (target does not exist) => [$wslTarget]"
		return
	}

	wsl -d $distro -u root mkdir -p $wslLinkDir
	wsl -d $distro -u root ln -sfn $wslTarget $wslLinkPath
	if ($LASTEXITCODE -eq 0) {
		Write-LogSuccess "Created WSL symlink => [$wslLinkPath] => [$wslTarget]"
	}
	else {
		Write-LogError "Failed to create WSL symlink => [$wslLinkPath]"
	}
}

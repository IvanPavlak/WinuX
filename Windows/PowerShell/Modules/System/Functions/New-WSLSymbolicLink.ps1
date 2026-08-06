function New-WSLSymbolicLink {
	<#
	.SYNOPSIS
		Creates a single symbolic link inside a WSL distribution.

	.DESCRIPTION
		Creates a symlink at Path pointing to Target inside the given WSL distribution
		(`ln -s`). The parent directory is created with `mkdir -p` if missing and any
		pre-existing file or symlink at Path is removed first.

		Every wsl.exe call targets the distribution explicitly (`wsl -d`) - Docker
		Desktop and podman machines routinely steal the WSL *default*, and a bare
		`wsl` would create the link inside the wrong distro.

		Never links to a missing target - that would delete the real file at Path and
		leave a dangling link; such calls are skipped with a warning and self-heal on
		the next run once the target exists.

	.PARAMETER Path
		Where the symlink is created (WSL path, e.g. "/home/user/.ssh/config").

	.PARAMETER Target
		What the symlink points to (WSL path, e.g. "/mnt/c/Users/User/.ssh/config").

	.PARAMETER Distribution
		The WSL distribution to create the link in (e.g. "Ubuntu").

	.PARAMETER DisplayName
		Label used in log messages (SymbolicLinkMaker passes the entry's dotted key,
		e.g. "WSLFastFetch.Configuration"). Defaults to Path.

	.EXAMPLE
		New-WSLSymbolicLink -Path "/home/user/.ssh/config" -Target "/mnt/c/Users/User/.ssh/config" -Distribution "Ubuntu"
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string]$Target,

		[Parameter(Mandatory)]
		[string]$Distribution,

		[string]$DisplayName = ""
	)

	if (-not $DisplayName) {
		$DisplayName = $Path
	}

	wsl -d $Distribution test -e $Target
	if ($LASTEXITCODE -ne 0) {
		Write-LogWarning "Skipped symlink (target does not exist) => [$DisplayName] => [$Target]"
		return
	}

	$lastSlashIndex = $Path.LastIndexOf('/')
	if ($lastSlashIndex -gt 0) {
		$parentDir = $Path.Substring(0, $lastSlashIndex)
		wsl -d $Distribution test -d $parentDir
		if ($LASTEXITCODE -ne 0) {
			wsl -d $Distribution mkdir -p $parentDir
			Write-LogSuccess "Created WSL directory => [$parentDir]"
		}
	}

	wsl -d $Distribution test -L $Path -o -f $Path
	if ($LASTEXITCODE -eq 0) {
		wsl -d $Distribution rm -f $Path
		if ($LASTEXITCODE -eq 0) {
			Write-LogWarning "Removed existing item => [$Path]"
		}
		else {
			Write-LogError "Failed to remove existing item => [$Path]"
		}
	}

	try {
		wsl -d $Distribution ln -s $Target $Path
		if ($LASTEXITCODE -eq 0) {
			Write-LogSuccess "Created WSL symlink => [$Path] => [$Target]"
		}
		else {
			Write-LogError "Failed to create WSL symlink for => $DisplayName"
		}
	}
	catch {
		Write-LogError "Failed to create WSL symlink for => $DisplayName => $($_.Exception.Message)"
	}
}

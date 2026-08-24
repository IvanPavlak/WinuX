function New-WSLSymbolicLink {
	<#
	.SYNOPSIS
		Creates a single symbolic link inside a WSL distribution, backing up whatever it replaces.

	.DESCRIPTION
		Creates a symlink at Path pointing to Target inside the given WSL distribution
		(`ln -s`). The parent directory is created with `mkdir -p` if missing.

		A REAL file already sitting at Path is copied out to the repository's backup
		folder on the Windows side before it is removed, so linking over a shell profile
		or an SSH config that only ever existed inside the distro never loses it. The
		copy lands in <Repo>\Backups\SymbolicLinks\<DisplayName>\<timestamp>\ and is
		gitignored - easy to find, never committed. When the backup cannot be written the
		link is skipped rather than removing an item that could not be saved first.

		An existing SYMLINK at Path is removed without a backup: it carries no content of
		its own, so archiving it would only pile up copies of WinuX's own links on every
		re-run.

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
		Label used in log messages and as the backup subfolder name (SymbolicLinkMaker
		passes the entry's dotted key, e.g. "WSLFastFetch.Configuration"). Defaults to Path.

	.PARAMETER BackupRoot
		Where replaced items are copied, as a WINDOWS path (it is translated into the
		distribution with `wslpath`). Defaults to <Repo>\Backups\SymbolicLinks.

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

		[string]$DisplayName = "",

		[string]$BackupRoot = ""
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
		wsl -d $Distribution test -L $Path
		$isLink = ($LASTEXITCODE -eq 0)

		if (-not $isLink) {
			if (-not $BackupRoot) {
				try {
					$BackupRoot = Join-Path -Path (Get-RepositoryPath -StartPath $PSScriptRoot).Repo -ChildPath "Backups\SymbolicLinks"
				}
				catch {
					Write-LogError "Skipped WSL symlink (cannot resolve the backup folder) => [$DisplayName] => $($_.Exception.Message)"
					return
				}
			}

			# One folder per entry, one timestamped folder per replacement, so every version ever
			# replaced stays side by side and the newest is last. DisplayName defaults to Path, so
			# strip the characters a path carries but a folder name cannot hold.
			$safeName = $DisplayName -replace '[\\/:*?"<>|]', '_'
			$backupDir = Join-Path -Path (Join-Path -Path $BackupRoot -ChildPath $safeName) -ChildPath (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')

			try {
				if (-not (Test-Path -LiteralPath $backupDir)) {
					New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
				}
			}
			catch {
				Write-LogError "Skipped WSL symlink (could not create the backup folder) => [$DisplayName] => $($_.Exception.Message)"
				return
			}

			# The backup folder is a Windows path; the copy happens inside the distro, so it has
			# to be expressed as one the distro understands (/mnt/c/...).
			$wslBackupDir = (wsl -d $Distribution wslpath -a "$backupDir" | Select-Object -First 1)
			if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslBackupDir)) {
				Write-LogError "Skipped WSL symlink (could not translate the backup folder for [$Distribution]) => [$DisplayName] => [$backupDir]"
				return
			}

			wsl -d $Distribution cp -a $Path "$($wslBackupDir.Trim())/"
			if ($LASTEXITCODE -ne 0) {
				Write-LogError "Skipped WSL symlink (could not back up the existing item) => [$DisplayName] => [$Path]"
				return
			}
			Write-LogWarning "Backed up existing item => [$Path] => [$backupDir]"
		}

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

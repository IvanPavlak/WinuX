function New-WSLSymbolicLink {
	<#
	.SYNOPSIS
		Creates a single symbolic link inside a WSL distribution, backing up whatever it replaces.

	.DESCRIPTION
		Creates a symlink at Path pointing to Target inside the given WSL distribution
		(`ln -s`). The parent directory is created with `mkdir -p` if missing.

		A REAL file already sitting at Path is copied out to the repository's unified
		backup sink on the Windows side before it is removed, so linking over a shell
		profile or an SSH config that only ever existed inside the distro never loses it.
		Backup-RepositoryItem creates the timestamped folder (the copy itself happens
		inside the distro with cp -a) and the copy lands in
		<Repo>\Backups\Windows\SymbolicLinks\<DisplayName>\<timestamp>\, gitignored - easy
		to find, never committed. When the backup cannot be written the link is skipped
		rather than removing an item that could not be saved first.

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
		Root of the unified backup sink replaced items are copied into, as a WINDOWS path
		(it is translated into the distribution with `wslpath`). Defaults to
		<Repo>\Backups\Windows.

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
			# The unified backup sink: one folder per entry, one timestamped folder per replacement.
			# The helper only creates the timestamped folder (-DirectoryOnly) - the copy itself has
			# to happen inside the distro so ownership and permissions survive (cp -a).
			try {
				$backupDir = Backup-RepositoryItem -Path $Path -Category "SymbolicLinks" -Key $DisplayName -BackupRoot $BackupRoot -DirectoryOnly
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
				try { Remove-Item -LiteralPath $backupDir -Force -ErrorAction Stop } catch { }
				return
			}

			wsl -d $Distribution cp -a $Path "$($wslBackupDir.Trim())/"
			if ($LASTEXITCODE -ne 0) {
				Write-LogError "Skipped WSL symlink (could not back up the existing item) => [$DisplayName] => [$Path]"
				try { Remove-Item -LiteralPath $backupDir -Force -ErrorAction Stop } catch { }
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

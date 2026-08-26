function New-WindowsSymbolicLink {
	<#
	.SYNOPSIS
		Creates a single native Windows symbolic link, backing up whatever it replaces.

	.DESCRIPTION
		Creates a symbolic link at Path pointing to Target. The parent directory is
		created if missing.

		A REAL file or directory already sitting at Path is copied into the repository's
		unified backup sink (via Backup-RepositoryItem) before it is removed, so linking
		over a hand-written PowerShell profile or an existing PowerToys settings file never
		loses it. The copy lands in <Repo>\Backups\Windows\SymbolicLinks\<DisplayName>\<timestamp>\
		and is gitignored - easy to find, never committed. When the backup cannot be written
		the link is skipped rather than removing an item that could not be saved first.

		An existing SYMLINK at Path is removed without a backup: it carries no content of
		its own, so archiving it would only pile up copies of WinuX's own links on every
		re-run.

		Never links to a missing target - that would delete the real file at Path,
		leave a dangling link, and pointlessly create parent folders; such calls are
		skipped with a warning and self-heal on the next run once the target exists.

		Requires administrator privileges (or Developer Mode).

	.PARAMETER Path
		Where the symbolic link is created.

	.PARAMETER Target
		What the symbolic link points to.

	.PARAMETER DisplayName
		Label used in log messages and as the backup subfolder name (SymbolicLinkMaker
		passes the entry's dotted key, e.g. "PowerToys.Settings"). Defaults to Path.

	.PARAMETER BackupRoot
		Root of the unified backup sink replaced items are copied into (under a
		SymbolicLinks\<DisplayName>\<timestamp> subpath). Defaults to <Repo>\Backups\Windows.

	.EXAMPLE
		New-WindowsSymbolicLink -Path "$env:USERPROFILE\.gitconfig" -Target "C:\Repo\Git\.gitconfig"

	.EXAMPLE
		New-WindowsSymbolicLink -Path "C:\link" -Target "C:\target" -BackupRoot "D:\Archive"
		Copies whatever C:\link was into D:\Archive\SymbolicLinks\... instead of the repository's
		Backups\Windows sink.
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string]$Target,

		[string]$DisplayName = "",

		[string]$BackupRoot = ""
	)

	if (-not $DisplayName) {
		$DisplayName = $Path
	}

	if (-not (Test-Path $Target)) {
		Write-LogWarning "Skipped symlink (target does not exist) => [$DisplayName] => [$Target]"
		return
	}

	$parentDir = Split-Path -Parent $Path
	if ($parentDir -and -not (Test-Path $parentDir)) {
		Initialize-Directory $parentDir
	}

	if (Test-Path -LiteralPath $Path) {
		$existing = Get-Item -LiteralPath $Path -Force
		$isLink = ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint

		if (-not $isLink) {
			# The unified backup sink: one folder per entry, one timestamped folder per replacement,
			# so every version ever replaced stays side by side and the newest is last. A backup
			# that cannot be taken skips the link rather than removing an item that was never saved.
			try {
				$backupDir = Backup-RepositoryItem -Path $Path -Category "SymbolicLinks" -Key $DisplayName -BackupRoot $BackupRoot
				Write-LogWarning "Backed up existing item => [$Path] => [$backupDir]"
			}
			catch {
				Write-LogError "Skipped symlink (could not back up the existing item) => [$DisplayName] => [$Path] => $($_.Exception.Message)"
				return
			}
		}

		# A real directory needs -Recurse to be removable at all; a symlink must NOT get it -
		# on a directory link -Recurse follows the link and deletes the TARGET's contents.
		if (-not $isLink -and $existing.PSIsContainer) {
			Remove-Item -LiteralPath $Path -Force -Recurse | Out-Null
		}
		else {
			Remove-Item -LiteralPath $Path -Force | Out-Null
		}
		Write-LogWarning "Removed existing item => [$Path]"
	}

	try {
		New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
		Write-LogSuccess "Created symlink => [$Path] => [$Target]"
	}
	catch {
		Write-LogError "Failed to create symlink for => $DisplayName => $($_.Exception.Message)"
	}
}

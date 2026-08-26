function Backup-RepositoryItem {
	<#
	.SYNOPSIS
		Copies an item into the repository's unified backup sink before it is replaced.

	.DESCRIPTION
		Every WinuX writer that is about to overwrite or displace an existing file calls this
		function first, so all replaced originals end up in one findable, OS-namespaced place:

			<Repo>\Backups\Windows\<Category>\<Key>\<yyyy-MM-dd_HH-mm-ss>\

		One folder per key, one timestamped folder per replacement - every version ever replaced
		stays side by side and the newest is last. The whole sink is gitignored (it holds your
		machine's data, which may include secrets) and bounded by Clear-OldBackups.

		After a successful copy the function opportunistically prunes the key's own folder down to
		Backups.Retention.MaxBackupsPerKey timestamped entries, so the sink stays bounded even on
		machines whose idle-time maintenance sweep never runs. Prune failures are ignored.

		On any failure the function throws AFTER removing a partially created backup folder, so a
		caller's try/catch can keep its contract: skip the replacement and leave the original
		untouched. A file that could not be backed up is never lost to a half-taken backup.

	.PARAMETER Path
		The existing file or directory to back up. Directories are copied recursively.

	.PARAMETER Category
		Taxonomy folder inside the sink grouping backups by what kind of writer took them:
		SymbolicLinks (files displaced by symlinks), Config (repo-owned configuration files),
		System (machine-local files WinuX overwrites outside the repo).

	.PARAMETER Key
		Display key naming what was backed up, typically the dotted configuration key
		(e.g. "PowerShell.Profile", "Configuration.local"). Becomes the per-key folder name;
		characters a path carries but a folder name cannot hold are replaced with underscores.

	.PARAMETER BackupRoot
		Root of the backup sink. Defaults to <Repo>\Backups\Windows resolved via
		Get-RepositoryPath. Pass explicitly to redirect backups (e.g. into a test sandbox).

	.PARAMETER DirectoryOnly
		Create and return the timestamped backup folder WITHOUT copying anything into it.
		For callers that must perform the copy themselves (e.g. New-WSLSymbolicLink copies
		inside the distro with cp -a).

	.EXAMPLE
		$backupDir = Backup-RepositoryItem -Path $PROFILE -Category SymbolicLinks -Key "PowerShell.Profile"
		Copies the profile into Backups\Windows\SymbolicLinks\PowerShell.Profile\<timestamp>\.

	.EXAMPLE
		$backupDir = Backup-RepositoryItem -Path "\\wsl$\Ubuntu\home\user\.bashrc" -Category SymbolicLinks -Key "WSLShell.Bashrc" -DirectoryOnly
		Creates the timestamped folder only; the caller copies the file into it itself.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[string]$Category,

		[Parameter(Mandatory)]
		[string]$Key,

		[string]$BackupRoot = "",

		[switch]$DirectoryOnly
	)

	if (-not $DirectoryOnly -and -not (Test-Path -LiteralPath $Path)) {
		throw "Backup-RepositoryItem: nothing exists at '$Path' to back up."
	}

	if (-not $BackupRoot) {
		$BackupRoot = Join-Path -Path (Get-RepositoryPath -StartPath $PSScriptRoot).Repo -ChildPath "Backups\Windows"
	}

	# Key defaults to a dotted config key but may be a raw path; strip the characters a path
	# carries but a folder name cannot hold (same rule for Category, defensively).
	$safeCategory = $Category -replace '[\\/:*?"<>|]', '_'
	$safeKey = $Key -replace '[\\/:*?"<>|]', '_'
	$keyDir = Join-Path -Path (Join-Path -Path $BackupRoot -ChildPath $safeCategory) -ChildPath $safeKey

	# One timestamped folder per replacement; a same-second second replacement gets a _2 suffix
	# rather than mixing two backups into one folder.
	$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
	$backupDir = Join-Path -Path $keyDir -ChildPath $stamp
	$suffix = 2
	while (Test-Path -LiteralPath $backupDir) {
		$backupDir = Join-Path -Path $keyDir -ChildPath "${stamp}_${suffix}"
		$suffix++
	}

	try {
		New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
		if (-not $DirectoryOnly) {
			Copy-Item -LiteralPath $Path -Destination $backupDir -Recurse -Force -ErrorAction Stop
		}
	}
	catch {
		# Never leave a half-taken backup behind - a partial folder would look like a good
		# restore point. Empty parents this call created go too. The original at $Path is
		# untouched either way.
		try { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction Stop } catch { }
		foreach ($parent in $keyDir, (Split-Path -Path $keyDir -Parent)) {
			if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue)) {
				try { Remove-Item -LiteralPath $parent -Force -ErrorAction Stop } catch { }
			}
		}
		throw
	}

	Write-Verbose "Backed up => [$Path] => [$backupDir]"

	# Opportunistic per-key prune so the sink stays bounded between maintenance sweeps. Only this
	# key's folder is touched; the full sweep (age + total size) belongs to Clear-OldBackups.
	if (-not $DirectoryOnly) {
		try {
			$maxPerKey = 10
			$retention = $global:Configuration.Backups.Retention
			if ($retention -and $null -ne $retention.MaxBackupsPerKey) { $maxPerKey = [int]$retention.MaxBackupsPerKey }
			if ($maxPerKey -gt 0) {
				$entries = @(Get-ChildItem -LiteralPath $keyDir -Directory -ErrorAction Stop |
						Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}' } |
						Sort-Object Name -Descending)
				foreach ($stale in ($entries | Select-Object -Skip $maxPerKey)) {
					try { Remove-Item -LiteralPath $stale.FullName -Recurse -Force -ErrorAction Stop } catch { }
				}
			}
		}
		catch { }
	}

	return $backupDir
}

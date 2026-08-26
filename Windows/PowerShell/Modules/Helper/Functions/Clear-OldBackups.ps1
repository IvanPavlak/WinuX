function Clear-OldBackups {
	<#
	.SYNOPSIS
		Enforces backup retention so Backups\Windows stays bounded but never loses the last copy.

	.DESCRIPTION
		Prunes the timestamped backup folders Backup-RepositoryItem creates under
		<Repo>\Backups\Windows\<Category>\<Key>\ by three independent limits, applied in order:
		maximum age in days, maximum number of backups per key, then maximum total size of the
		whole sink in megabytes (oldest removed first).

		Unlike logs, a replaced original is not regenerable, so THE NEWEST BACKUP OF EVERY KEY IS
		NEVER DELETED by any limit. Key and category folders left empty by pruning are removed;
		the tracked Backups\.gitkeep sits above the sink root and is never touched. Backups taken
		by versions of WinuX older than the unified sink (directly under Backups\SymbolicLinks)
		are outside the root this function scans and are never pruned.

		Called automatically by the idle-time Invoke-LogMaintenance sweep; safe to run manually at
		any time. Limits default from $Configuration.Backups.Retention.

	.PARAMETER MaxAgeDays
		Delete backups older than this many days. Default from config (fallback 0 = never;
		replaced originals are precious, so age pruning ships disabled).

	.PARAMETER MaxBackupsPerKey
		Keep at most this many timestamped backups per key (newest retained). Default from config
		(fallback 10). 0 = unlimited.

	.PARAMETER MaxTotalSizeMB
		Cap the combined size of the whole sink in MB (oldest removed first, newest-per-key kept).
		Default from config (fallback 500). 0 = uncapped.

	.PARAMETER BackupRoot
		Root of the backup sink to prune. Defaults to <Repo>\Backups\Windows resolved via
		Get-RepositoryPath. Pass explicitly to prune a test sandbox.

	.EXAMPLE
		Clear-OldBackups
		Prune using the configured retention limits.

	.EXAMPLE
		Clear-OldBackups -MaxBackupsPerKey 3
		Keep only the three newest backups of every key.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[int]$MaxAgeDays,

		[Parameter(Mandatory = $false)]
		[int]$MaxBackupsPerKey,

		[Parameter(Mandatory = $false)]
		[int]$MaxTotalSizeMB,

		[string]$BackupRoot = ""
	)

	if (-not $BackupRoot) {
		try {
			$BackupRoot = Join-Path -Path (Get-RepositoryPath -StartPath $PSScriptRoot).Repo -ChildPath "Backups\Windows"
		}
		catch { return }
	}
	if (-not (Test-Path -LiteralPath $BackupRoot)) { return }

	$retention = $null
	if ($global:Configuration -and $global:Configuration.Backups -and $global:Configuration.Backups.Retention) {
		$retention = $global:Configuration.Backups.Retention
	}

	if (-not $PSBoundParameters.ContainsKey('MaxAgeDays')) { $MaxAgeDays = if ($retention -and $null -ne $retention.MaxAgeDays) { [int]$retention.MaxAgeDays } else { 0 } }
	if (-not $PSBoundParameters.ContainsKey('MaxBackupsPerKey')) { $MaxBackupsPerKey = if ($retention -and $null -ne $retention.MaxBackupsPerKey) { [int]$retention.MaxBackupsPerKey } else { 10 } }
	if (-not $PSBoundParameters.ContainsKey('MaxTotalSizeMB')) { $MaxTotalSizeMB = if ($retention -and $null -ne $retention.MaxTotalSizeMB) { [int]$retention.MaxTotalSizeMB } else { 500 } }

	# The sink is <root>\<category>\<key>\<yyyy-MM-dd_HH-mm-ss[_n]>\. Timestamped names sort
	# chronologically as plain strings, so Name ordering is creation ordering.
	$getKeyDirs = {
		Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
			ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue }
	}
	$getBackups = {
		param($keyDir)
		@(Get-ChildItem -LiteralPath $keyDir.FullName -Directory -ErrorAction SilentlyContinue |
				Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}' } |
				Sort-Object Name -Descending)
	}

	# 1) Age - the newest backup of a key survives even past the cutoff.
	if ($MaxAgeDays -gt 0) {
		$cutoff = (Get-Date).AddDays(-$MaxAgeDays)
		foreach ($keyDir in (& $getKeyDirs)) {
			$backups = & $getBackups $keyDir
			foreach ($backup in ($backups | Select-Object -Skip 1)) {
				if ($backup.LastWriteTime -lt $cutoff) {
					try { Remove-Item -LiteralPath $backup.FullName -Recurse -Force -ErrorAction Stop } catch { }
				}
			}
		}
	}

	# 2) Per-key count (keep newest N; N is at least 1 because Skip is never below 1).
	if ($MaxBackupsPerKey -gt 0) {
		foreach ($keyDir in (& $getKeyDirs)) {
			$backups = & $getBackups $keyDir
			foreach ($stale in ($backups | Select-Object -Skip ([Math]::Max($MaxBackupsPerKey, 1)))) {
				try { Remove-Item -LiteralPath $stale.FullName -Recurse -Force -ErrorAction Stop } catch { }
			}
		}
	}

	# 3) Total size across the whole sink (remove oldest first, never a key's last backup).
	if ($MaxTotalSizeMB -gt 0) {
		$capBytes = [int64]$MaxTotalSizeMB * 1MB
		$all = foreach ($keyDir in (& $getKeyDirs)) {
			$backups = & $getBackups $keyDir
			for ($i = 0; $i -lt $backups.Count; $i++) {
				$size = (Get-ChildItem -LiteralPath $backups[$i].FullName -Recurse -File -ErrorAction SilentlyContinue |
						Measure-Object -Property Length -Sum).Sum
				if ($null -eq $size) { $size = 0 }
				[pscustomobject]@{ Dir = $backups[$i]; Size = [int64]$size; IsNewestOfKey = ($i -eq 0) }
			}
		}
		$all = @($all | Where-Object { $_ })
		$total = ($all | Measure-Object -Property Size -Sum).Sum
		if ($null -eq $total) { $total = 0 }
		$ordered = @($all | Where-Object { -not $_.IsNewestOfKey } | Sort-Object { $_.Dir.Name })  # oldest first
		$index = 0
		while ($total -gt $capBytes -and $index -lt $ordered.Count) {
			$victim = $ordered[$index]
			try {
				Remove-Item -LiteralPath $victim.Dir.FullName -Recurse -Force -ErrorAction Stop
				$total -= $victim.Size
			}
			catch { }
			$index++
		}
	}

	# Remove key and category folders left empty by the pruning above (innermost first).
	foreach ($keyDir in (& $getKeyDirs)) {
		if (-not (Get-ChildItem -LiteralPath $keyDir.FullName -Force -ErrorAction SilentlyContinue)) {
			try { Remove-Item -LiteralPath $keyDir.FullName -Force -ErrorAction Stop } catch { }
		}
	}
	foreach ($categoryDir in (Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue)) {
		if (-not (Get-ChildItem -LiteralPath $categoryDir.FullName -Force -ErrorAction SilentlyContinue)) {
			try { Remove-Item -LiteralPath $categoryDir.FullName -Force -ErrorAction Stop } catch { }
		}
	}
}

function Save-ConfigurationFile {
	<#
	.SYNOPSIS
		Writes a configuration file an Add-* writer edited, after backing the old one up.
	.DESCRIPTION
		Copies the existing file into the unified backup sink of the repository it belongs to
		(Backups\Windows\Config\<file name without extension>\<timestamp>\) as a one-click undo,
		then writes the new lines. A backup that cannot be taken aborts the write and leaves the
		file untouched. A file that does not exist yet (a Configuration.local.psd1 created by the
		write) has nothing to back up and is written directly.
	.PARAMETER Path
		The configuration file to write.
	.PARAMETER Lines
		The complete new content, one line per element.
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the file
		belongs to.
	.OUTPUTS
		[bool] $true when the file was written, $false when the backup failed.
	.EXAMPLE
		if (-not (Save-ConfigurationFile -Path $target.Path -Lines $newLines)) { return }
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[AllowEmptyCollection()]
		[string[]]$Lines,

		[string]$BackupRoot
	)

	if (Test-Path $Path) {
		try {
			if (-not $BackupRoot) {
				$BackupRoot = Join-Path -Path (Get-RepositoryPath -StartPath (Split-Path -Path $Path -Parent)).Repo -ChildPath "Backups\Windows"
			}
			$backupKey = [System.IO.Path]::GetFileNameWithoutExtension($Path)
			Backup-RepositoryItem -Path $Path -Category "Config" -Key $backupKey -BackupRoot $BackupRoot | Out-Null
		}
		catch {
			Write-LogError "Could not back up '$Path'; aborting without changes. $($_.Exception.Message)"
			return $false
		}
	}

	Set-Content -Path $Path -Value $Lines
	return $true
}

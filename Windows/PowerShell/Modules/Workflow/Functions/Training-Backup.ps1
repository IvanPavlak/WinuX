function Training-Backup {
	<#
	.SYNOPSIS
		Runs the training backup batch script in its configured directory.

	.DESCRIPTION
		DEPRECATED since 2.17.0, removed in 3.0.0: it serves one personal setup rather than
		the framework. It keeps working unchanged until then and warns once per session; to keep
		it, copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom).

		Navigates to `$MachineSpecificPaths.TrainingBackupDirectory` and executes
		`TrainingBackup.bat`. Restores the original working directory on exit.

		The backup script and its directory are external to this WinuX repository.

	.EXAMPLE
		Training-Backup
		Runs the training backup script.
	#>

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Training-Backup']) {
		$global:WinuXDeprecationWarned['Training-Backup'] = $true
		Write-LogWarning "Training-Backup is deprecated since 2.17.0 and removed in 3.0.0 - copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom) to keep using it"
	}

	$currentDirectory = Get-Location

	try {
		& ".\TrainingBackup.bat"
		Write-LogSuccess "Training Backup Completed!"
	}
	catch {
		Write-LogError "Error during Training Backup!"
		Write-LogError $_.Exception.Message -NoLeadingNewline
	}
	finally {
		Set-Location -Path $currentDirectory
	}
}

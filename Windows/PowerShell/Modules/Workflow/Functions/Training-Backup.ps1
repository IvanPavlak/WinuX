function Training-Backup {
	<#
	.SYNOPSIS
		Runs the training backup batch script in its configured directory.

	.DESCRIPTION
		Navigates to `$MachineSpecificPaths.TrainingBackupDirectory` and executes
		`TrainingBackup.bat`. Restores the original working directory on exit.

		The backup script and its directory are external to this WinuX repository.

	.EXAMPLE
		Training-Backup
		Runs the training backup script.
	#>
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

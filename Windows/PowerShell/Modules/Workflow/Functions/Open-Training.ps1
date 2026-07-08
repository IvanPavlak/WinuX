function Open-Training {
	<#
	.SYNOPSIS
		Opens the training Word document in Microsoft Word.

	.DESCRIPTION
		Opens the training file configured at `$Configuration.Universal.TrainingFile` from
		the `$MachineSpecificPaths.TrainingDirectory`. Does nothing if Word is already running.

	.EXAMPLE
		Open-Training
		Opens the training document in Microsoft Word.
	#>
	if (-not (Get-Process -Name "WINWORD" -ErrorAction SilentlyContinue)) {
		try {
			Start-Process "winword" -ArgumentList (Join-Path $MachineSpecificPaths.TrainingDirectory $Configuration.Universal.TrainingFile) -ErrorAction Stop
			Write-LogStep "Opening training file..."
			Write-LogSuccess "Training file opened!"
		}
		catch {
			Write-LogError "Error: $($_.Exception.Message)"
		}
	}
	else {
		Write-LogWarning "Training file is already opened!"
	}
}

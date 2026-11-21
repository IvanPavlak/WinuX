function Open-Training {
	<#
	.SYNOPSIS
		Opens the training Word document in Microsoft Word.

	.DESCRIPTION
		DEPRECATED since 2.17.0, removed in 3.0.0: it serves one personal setup rather than
		the framework. It keeps working unchanged until then and warns once per session; to keep
		it, copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom).

		Opens the training file configured at `$Configuration.Universal.TrainingFile` from
		the `$MachineSpecificPaths.TrainingDirectory`. Does nothing if Word is already running.

	.EXAMPLE
		Open-Training
		Opens the training document in Microsoft Word.
	#>

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Open-Training']) {
		$global:WinuXDeprecationWarned['Open-Training'] = $true
		Write-LogWarning "Open-Training is deprecated since 2.17.0 and removed in 3.0.0 - copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom) to keep using it"
	}

	if (-not (Get-Process -Name "WINWORD" -ErrorAction SilentlyContinue)) {
		try {
			$trainingFile = Get-ConfigSetting -Path 'Universal.TrainingFile'
			Start-Process "winword" -ArgumentList (Join-Path $MachineSpecificPaths.TrainingDirectory $trainingFile) -ErrorAction Stop
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

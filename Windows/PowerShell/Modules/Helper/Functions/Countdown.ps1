function Countdown {
	<#
	.SYNOPSIS
		Display a colored countdown timer.

	.DESCRIPTION
		Shows a countdown from specified seconds to zero with optional message.
		Counts >3 in dark cyan, <=3 in red. Used before destructive operations.

	.PARAMETER Seconds
		Number of seconds to count down from (required).

	.PARAMETER Message
		Optional message to display before countdown starts.

	.EXAMPLE
		Countdown -Seconds 5 -Message "Restarting in:"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[int]$Seconds,

		[Parameter(Mandatory = $false)]
		[string]$Message
	)

	if ($Message) {
		Write-Host -ForegroundColor White "`n $Message`n"
	}

	for ($i = $Seconds; $i -gt 0; $i--) {
		if ($i -gt 3) {
			Write-Host -ForegroundColor DarkCyan " $i"
		}
		else {
			Write-Host -ForegroundColor Red " $i"
		}
		Start-Sleep -Seconds 1
	}
}

function Restart-Explorer {
	<#
	.SYNOPSIS
		Restarts Windows Explorer.

	.DESCRIPTION
		Stops the Explorer process and waits before it auto-restarts.
		An optional message is displayed with a loading spinner during the wait.

	.PARAMETER Message
		Label to display in the loading spinner during the delay. Omit for no spinner.

	.PARAMETER Delay
		Seconds to wait after stopping Explorer before continuing. Defaults to 1.

	.EXAMPLE
		Restart-Explorer
		Restarts Explorer with a 1-second delay.

	.EXAMPLE
		Restart-Explorer -Message "Waiting for Explorer..." -Delay 3
		Restarts Explorer and shows a spinner for 3 seconds.
	#>
	param(
		[Parameter(Mandatory = $false)]
		[string]$Message = "",
		[Parameter(Mandatory = $false)]
		[int]$Delay = 1
	)

	Write-LogTitle "Restarting Explorer"
	Stop-Process -processname explorer

	$sleepScript = [scriptblock]::Create("Start-Sleep $Delay")

	if ($Message) {
		Loading-Spinner -Function $sleepScript -Label $Message
	}
	else {
		Loading-Spinner -Function $sleepScript
	}
}

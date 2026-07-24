function Restart-Explorer {
	<#
	.SYNOPSIS
		Restarts Windows Explorer.

	.DESCRIPTION
		Stops the Explorer process and waits before it auto-restarts.
		An optional message is displayed with a loading spinner during the wait.

		An Explorer restart disconnects any VirtualDesktop COM proxies this session
		has cached (every later call would fail with "The RPC server is unavailable",
		0x800706BA). When the VirtualDesktop types are loaded in this process, the
		session is proactively reconnected via Reset-VirtualDesktopState after the
		wait, with bounded retries while the new Explorer instance re-registers its
		COM classes.

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

	# Reconnect this session's VirtualDesktop COM state, which the restart just
	# severed. Only relevant when the compiled types already exist in this process;
	# a session that never used VirtualDesktop has nothing to reconnect. The retry
	# loop rides out the window where the fresh Explorer instance has not finished
	# re-registering its COM classes yet.
	$desktopTypesLoaded = $null -ne ([System.Management.Automation.PSTypeName]'VirtualDesktop.Desktop').Type
	if ($desktopTypesLoaded -and (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue)) {
		for ($attempt = 1; $attempt -le 5; $attempt++) {
			if (Reset-VirtualDesktopState) {
				Write-LogDebug "  Reconnected VirtualDesktop session after Explorer restart (attempt $attempt)" -Style Success
				break
			}
			Start-Sleep -Milliseconds (400 * $attempt)
		}
	}
}

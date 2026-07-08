function Test-MachineOnline {
	<#
	.SYNOPSIS
		Tests whether a machine is online (reachable via ICMP ping).

	.DESCRIPTION
		Pings a machine to determine whether it is currently powered on and
		reachable on the network. The target is resolved from the `Address` field
		of `WakeOnLanConfig` in Configuration.psd1 (by machine name), or supplied
		directly as an IP address / hostname.

		Two modes are supported:
		  - Single check (default): pings once and returns the result.
		  - Wait-for-online (`-WaitForOnline`): polls repeatedly until the machine
		    responds or `-TimeoutSeconds` elapses. Send-WakeOnLan uses this to
		    confirm that a machine has actually finished booting after a magic
		    packet is sent, instead of blindly assuming the wake succeeded.

		Returns a boolean so it can be used in conditional logic. If a machine has
		no `Address` configured, reachability cannot be determined and the function
		returns `$false`.

	.PARAMETER Machine
		Machine name as defined in WakeOnLanConfig. The machine's `Address` field
		is used as the ping target.

	.PARAMETER Address
		Explicit IP address or hostname to ping. Use instead of -Machine when the
		address is already known (Send-WakeOnLan passes this directly).

	.PARAMETER DisplayName
		Friendly name used in console messages. Defaults to -Machine or -Address.

	.PARAMETER WaitForOnline
		Poll repeatedly until the machine responds or -TimeoutSeconds is reached.

	.PARAMETER TimeoutSeconds
		Maximum time to wait when -WaitForOnline is used. Default 120.

	.PARAMETER IntervalSeconds
		Delay between ping attempts when -WaitForOnline is used. Default 3.

	.PARAMETER PingTimeoutMilliseconds
		Per-ping timeout in milliseconds. Default 1000.

	.PARAMETER Quiet
		Suppress all console output and only return the boolean result.

	.OUTPUTS
		System.Boolean. $true if the machine responded, otherwise $false.

	.EXAMPLE
		Test-MachineOnline -Machine "Server"
		Pings the Server once and reports whether it is online.

	.EXAMPLE
		if (Test-MachineOnline -Machine "PC" -Quiet) { "PC is already up" }
		Uses the result in a condition without printing anything.

	.EXAMPLE
		Test-MachineOnline -Address "192.168.1.10" -WaitForOnline -TimeoutSeconds 90
		Polls 192.168.1.10 for up to 90 seconds, returning once it responds.
	#>
	[CmdletBinding(DefaultParameterSetName = "Machine")]
	[OutputType([bool])]
	param(
		[Parameter(Position = 0, ParameterSetName = "Machine")]
		[string]$Machine,

		[Parameter(Mandatory = $true, ParameterSetName = "Address")]
		[string]$Address,

		[string]$DisplayName,

		[switch]$WaitForOnline,

		[int]$TimeoutSeconds = 120,

		[int]$IntervalSeconds = 3,

		[int]$PingTimeoutMilliseconds = 1000,

		[switch]$Quiet
	)

	# Resolve the target address (explicit -Address, or the machine's Address from config)
	$targetAddress = $Address
	$label = if ($DisplayName) { $DisplayName } elseif ($Address) { $Address } else { $Machine }

	if (-not $targetAddress) {
		$wolConfig = $Configuration.WakeOnLanConfig
		if (-not $wolConfig) {
			if (-not $Quiet) { Write-LogError "Error => WakeOnLanConfig not found in configuration!" }
			return $false
		}

		if (-not $Machine -or -not $wolConfig.ContainsKey($Machine)) {
			if (-not $Quiet) { Write-LogError "Error => Configuration for machine [$Machine] not found in WakeOnLanConfig!" }
			return $false
		}

		$targetAddress = $wolConfig[$Machine].Address
	}

	if (-not $targetAddress) {
		if (-not $Quiet) {
			Write-LogWarning "Warning => No [Address] configured for [$label]! Cannot test reachability!"
		}
		return $false
	}

	$ping = New-Object System.Net.NetworkInformation.Ping
	$successStatus = [System.Net.NetworkInformation.IPStatus]::Success

	# Single ping attempt. Reads $ping / $targetAddress / $PingTimeoutMilliseconds
	# from the enclosing scope; returns $false on any failure (down host, DNS error).
	$pingOnce = {
		try {
			$reply = $ping.Send($targetAddress, $PingTimeoutMilliseconds)
			return ($reply.Status -eq $successStatus)
		}
		catch {
			return $false
		}
	}

	try {
		if (-not $WaitForOnline) {
			$isOnline = & $pingOnce
			if (-not $Quiet) {
				if ($isOnline) {
					Write-LogSuccess "[$label] is online ($targetAddress)!"
				}
				else {
					Write-LogWarning "[$label] is offline ($targetAddress)!"
				}
			}
			return $isOnline
		}

		# Wait-for-online: poll until the machine responds or the timeout elapses.
		if (-not $Quiet) {
			Write-LogStep "Waiting for [$label] to come online (timeout ${TimeoutSeconds}s)..."
		}

		$consoleWidth = 80
		try { if ([Console]::WindowWidth -gt 10) { $consoleWidth = [Console]::WindowWidth - 1 } } catch { }
		$lineFormat = "`r{0,-$consoleWidth}"

		$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
		$attempt = 0

		while ((Get-Date) -lt $deadline) {
			$attempt++

			if (& $pingOnce) {
				if (-not $Quiet) {
					Write-Host -ForegroundColor Green ($lineFormat -f " => [$label] is online ($targetAddress)!")
				}
				return $true
			}

			if (-not $Quiet) {
				$remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
				if ($remaining -lt 0) { $remaining = 0 }
				$status = "  Waiting for [$label] to wake... ${remaining}s remaining (attempt $attempt)"
				if ($status.Length -gt $consoleWidth) { $status = $status.Substring(0, $consoleWidth) }
				Write-Host -NoNewline -ForegroundColor DarkCyan ($lineFormat -f $status)
			}

			Start-Sleep -Seconds $IntervalSeconds
		}

		if (-not $Quiet) {
			Write-Host -ForegroundColor Red ($lineFormat -f " => [$label] did not respond within ${TimeoutSeconds}s ($targetAddress)!")
		}
		return $false
	}
	finally {
		$ping.Dispose()
	}
}

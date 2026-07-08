function Send-WakeOnLan {
	<#
	.SYNOPSIS
		Sends a Wake-on-LAN magic packet to one or more machines.

	.DESCRIPTION
		Reads machine configurations from `WakeOnLanConfig` in Configuration.psd1.
		When called with machine names, sends magic packets to those machines.
		When called without arguments, shows an interactive menu of available machines.
		Each machine entry should specify a MAC address, broadcast address and port.

		If a machine also has an `Address` (IP or hostname) configured, the function
		uses Test-MachineOnline to make Wake-on-LAN reliable instead of fire-and-forget:
		  - Before sending, it pings the machine. If it is already online, the magic
		    packet is skipped (no point waking a machine that is already awake).
		  - After sending, it polls the machine until it responds or -TimeoutSeconds
		    elapses, so the result reflects whether the machine actually woke up.

		Machines without an `Address` fall back to the original fire-and-forget
		behaviour (send the packet, no ping check, no verification).

	.PARAMETER Machine
		One or more machine names as defined in Configuration.psd1.
		Omit to show the interactive menu.

	.PARAMETER TimeoutSeconds
		Maximum seconds to wait for a machine to come online after the packet is
		sent (verification phase). Default 120.

	.PARAMETER NoWait
		Send the magic packet without the online pre-check or post-send
		verification (original fire-and-forget behaviour).

	.EXAMPLE
		Send-WakeOnLan
		Shows the machine selection menu.

	.EXAMPLE
		Send-WakeOnLan -Machine "Server"
		Wakes the Server, skipping it if already on, then waits until it responds.

	.EXAMPLE
		Send-WakeOnLan -Machine "Server" -NoWait
		Sends the magic packet only, without pinging or waiting for confirmation.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$Machine,

		[int]$TimeoutSeconds = 120,

		[switch]$NoWait
	)

	$wolConfig = $Configuration.WakeOnLanConfig
	if (-not $wolConfig) {
		Write-LogError "Error: WakeOnLanConfig not found in configuration!"
		return
	}

	$defaultMachine = $Configuration.DefaultWakeOnLanMachine

	$resolveParams = @{
		InputObject              = $Machine
		OptionList               = $Configuration.WakeOnLanMachines
		MenuTitle                = "[Available Machines for Wake-on-LAN]"
		PromptMessage            = "Select machine to wake (Press Enter for default => $defaultMachine)"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}

	$machines = Resolve-Selection @resolveParams

	if ($machines -contains "None") {
		Write-LogWarning "Wake-on-LAN cancelled!"

		#Open-Browser LocalLinks

		return
	}

	if ($machines -contains "All") {
		Write-LogStep "Waking all configured machines..."
		$machines = $wolConfig.Keys | Where-Object { $_ -notin @("All", "None") }
	}

	#Open-Browser DomainLinks

	if (-not $machines) {
		if ($defaultMachine) {
			$machines = @($defaultMachine)
		}
		else {
			return
		}
	}

	try {
		foreach ($machineName in $machines) {
			if (-not $wolConfig.ContainsKey($machineName)) {
				Write-LogError "Error => Configuration for machine [$machineName] not found in WakeOnLanConfig!"
				continue
			}

			$config = $wolConfig[$machineName]
			$mac = $config.MacAddress
			$broadcastAddress = $config.SubNetSpecificBroadcastAddress
			$port = $config.Port
			$address = $config.Address

			if (-not $mac -or -not $broadcastAddress -or -not $port) {
				Write-LogError "Error: Missing configuration for machine [$machineName]!"
				continue
			}

			# Already awake? Then there is nothing to wake - skip the packet.
			if (-not $NoWait -and $address -and (Test-MachineOnline -Address $address -DisplayName $machineName -Quiet)) {
				Write-LogSuccess "[$machineName] is already online ($address)! Skipping Wake-on-LAN!"
				continue
			}

			# Build magic packet
			$macByteArray = $mac -split "[:-]" | ForEach-Object { [Byte] "0x$_" }
			[Byte[]] $magicPacket = (, 0xFF * 6) + ($macByteArray * 16)

			# Send WOL packet
			Write-LogStep "Sending Wake-on-LAN to [$machineName]..."
			Write-Verbose "MAC: $mac, Broadcast: $broadcastAddress, Port: $port"

			$udpClient = New-Object System.Net.Sockets.UdpClient
			$udpClient.EnableBroadcast = $true
			$udpClient.Connect(([System.Net.IPAddress]::Parse($broadcastAddress)), $port)
			$null = $udpClient.Send($magicPacket, $magicPacket.Length)
			$udpClient.Close()

			Write-LogSuccess "Wake-on-LAN packet sent to [$machineName] ($mac)!"

			# Confirm the machine actually woke up (the whole point of pinging).
			if ($NoWait) {
				continue
			}

			if (-not $address) {
				Write-LogWarning "No [Address] configured for [$machineName]! Cannot confirm it woke up! Add an [Address] to WakeOnLanConfig to enable verification!"
				continue
			}

			if (Test-MachineOnline -Address $address -DisplayName $machineName -WaitForOnline -TimeoutSeconds $TimeoutSeconds) {
				Write-LogSuccess "[$machineName] is now awake and reachable!"
			}
			else {
				Write-LogError "[$machineName] did not respond within $TimeoutSeconds seconds. It may still be booting, or Wake-on-LAN may need attention (BIOS/NIC 'Wake on Magic Packet' setting, correct MAC, or a wired connection)!"
			}
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)"
	}
}

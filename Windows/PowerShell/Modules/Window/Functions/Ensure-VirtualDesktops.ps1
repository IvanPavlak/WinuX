# VirtualDesktop RPC can go stale after COM-heavy shell operations (Explorer restarts,
# wallpaper/taskbar changes); operations run under RPC-aware retries and reconnect the
# session's COM proxies (Reset-VirtualDesktopState) between attempts when that happens.
function Ensure-VirtualDesktops {
	<#
	.SYNOPSIS
		Ensures the specified number of virtual desktops exist.

	.DESCRIPTION
		Creates virtual desktops if they don't exist, up to the specified count.
		Requires the VirtualDesktop PowerShell module.

		Runs a live RPC preflight (Get-RpcRetryPolicy -Probe) before touching
		desktops, and wraps every VirtualDesktop call in retry helpers with an
		RPC-aware recovery hook: when an operation fails with the RPC-unavailable
		family of errors (0x800706BA and friends - the state an Explorer restart
		leaves behind), the session's VirtualDesktop COM proxies are reconnected via
		Reset-VirtualDesktopState before the next attempt, so the session heals in
		place instead of failing until a new shell is opened.

	.PARAMETER Count
		The total number of virtual desktops that should exist.

	.PARAMETER SwitchToDesktop
		If specified, switches to the specified desktop number (1-based) after ensuring desktops exist.

	.EXAMPLE
		Ensure-VirtualDesktops -Count 3

	.EXAMPLE
		Ensure-VirtualDesktops -Count 4 -SwitchToDesktop 1
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$Count,

		[Parameter()]
		[int]$SwitchToDesktop = 0
	)

	# Use cached VirtualDesktop module loader
	if (-not (Import-VirtualDesktopModule)) {
		Write-Error "VirtualDesktop module not found. Please install it:"
		Write-LogWarning "Install-Module -Name VirtualDesktop -Scope CurrentUser" -NoLeadingNewline
		Write-LogStep "Or visit: https://github.com/MScholtes/PSVirtualDesktop" -NoLeadingNewline
		return $false
	}

	$rpcPolicy = if (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue) {
		Get-RpcRetryPolicy -OperationLabel "ensuring virtual desktops" -MaxAttempts 5 -InitialDelayMs 250 -Probe
	}
	else {
		@{ MaxAttempts = 5; InitialDelayMs = 250 }
	}
	$rpcMaxAttempts = [int]$rpcPolicy.MaxAttempts
	$rpcInitialDelayMs = [int]$rpcPolicy.InitialDelayMs
	$useRetry = [bool](Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)
	$useOptionalRetryHelper = [bool](Get-Command Invoke-WithOptionalRetry -ErrorAction SilentlyContinue)

	$rpcUnavailablePattern = '0x800706BA|0x800706BE|0x80010108|RPC server is unavailable|The remote procedure call failed'
	$recoverVirtualDesktopRpc = {
		param($ErrorRecord, [int]$Attempt)

		$isRpcFailure = if (Get-Command Test-RpcUnavailableError -ErrorAction SilentlyContinue) {
			Test-RpcUnavailableError $ErrorRecord
		}
		else {
			$errorMessage = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
			$errorMessage -match $rpcUnavailablePattern
		}
		if (-not $isRpcFailure) {
			return
		}

		Write-LogDebug "  RPC endpoint unavailable while ensuring desktops; resetting VirtualDesktop state before retry $($Attempt + 1)" -Style Warning -NoLeadingNewline

		if (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue) {
			[void](Reset-VirtualDesktopState)
			return
		}

		try {
			Remove-Module -Name VirtualDesktop -Force -ErrorAction SilentlyContinue
			Import-Module VirtualDesktop -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		}
		catch {
			# Best-effort recovery before the next retry attempt.
		}
	}

	$invokeDesktopOperation = {
		param([scriptblock]$Operation)

		if ($useOptionalRetryHelper) {
			return Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs -OnRetry $recoverVirtualDesktopRpc
		}

		if ($useRetry) {
			return Invoke-WithRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs -OnRetry $recoverVirtualDesktopRpc
		}

		return & $Operation
	}

	try {

		# Get current desktops using correct command
		$desktops = & $invokeDesktopOperation { Get-DesktopList }
		$currentCount = ($desktops | Measure-Object).Count

		Write-LogDebug "[Ensuring $Count virtual desktops exist]"
		Write-LogDebug "Existing desktop count => [$currentCount]" -Style Step
		Write-LogDebug "Required desktop count => [$Count]" -Style Warning

		if ($currentCount -lt $Count) {
			$toCreate = $Count - $currentCount
			Write-LogDebug "Creating [$toCreate] additional virtual desktop(s)..." -Style Warning

			for ($i = 0; $i -lt $toCreate; $i++) {
				[void](& $invokeDesktopOperation { New-Desktop > $null })
				Write-LogDebug "Created desktop [$($currentCount + $i + 1)]" -Style Success

				Start-Sleep -Milliseconds $script:WindowModuleDelays.VirtualDesktopMs
			}

			# Verify desktops were created
			$desktops = & $invokeDesktopOperation { Get-DesktopList }
			$finalCount = ($desktops | Measure-Object).Count
			if ($finalCount -lt $Count) {
				Write-Error "Failed to create required virtual desktops. Expected [$Count], found [$finalCount]."
				return $false
			}
			Write-LogDebug "Successfully created [$toCreate] virtual desktop(s)" -Style Success
			Write-LogDebug " Total virtual desktops => [$finalCount]" -Style Success
		}
		elseif ($currentCount -gt $Count) {
			Write-LogDebug " There are more desktops ($currentCount) than required ($Count)!" -Style Warning
			Write-LogDebug " Removing extra virtual desktops !" -Style Success
			try {
				$desktops = & $invokeDesktopOperation { Get-DesktopList }
				$currentCount = ($desktops | Measure-Object).Count

				while ($currentCount -gt $Count) {
					$desktopToRemove = $currentCount - 1
					[void](& $invokeDesktopOperation { Remove-Desktop -Desktop $desktopToRemove -Verbose:$false -ErrorAction Stop })
					$desktops = & $invokeDesktopOperation { Get-DesktopList }
					$currentCount = ($desktops | Measure-Object).Count
				}

				[void](& $invokeDesktopOperation { Switch-Desktop -Desktop 0 })
			}
			catch {
				Write-LogDebug "Could not remove virtual desktops => [$_]" -Style Error
				return $false
			}
		}
		else {
			Write-LogDebug "All required virtual desktops already exist!" -Style Success
		}

		# Switch to specific desktop if requested
		if ($SwitchToDesktop -gt 0 -and $SwitchToDesktop -le $Count) {
			# Convert 1-based to 0-based for VirtualDesktop module
			$internalDesktopIndex = $SwitchToDesktop - 1
			[void](& $invokeDesktopOperation { Switch-Desktop -Desktop $internalDesktopIndex })
			Write-LogDebug "Switched to virtual desktop [$SwitchToDesktop]"
		}

		return $true
	}
	catch {
		Write-Error "Failed to manage virtual desktops: $_"
		return $false
	}
}

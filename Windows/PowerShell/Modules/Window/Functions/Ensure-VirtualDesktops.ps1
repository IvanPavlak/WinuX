# KNOWN ISSUE: "The RPC server is unavailable. (0x800706BA)" occurs if this is called closely with Set-Wallpaper
function Ensure-VirtualDesktops {
	<#
	.SYNOPSIS
		Ensures the specified number of virtual desktops exist.

	.DESCRIPTION
		Creates virtual desktops if they don't exist, up to the specified count.
		Requires the VirtualDesktop PowerShell module.

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
		Get-RpcRetryPolicy -OperationLabel "ensuring virtual desktops"
	}
	else {
		@{ MaxAttempts = 3; InitialDelayMs = 200 }
	}
	$rpcMaxAttempts = [int]$rpcPolicy.MaxAttempts
	$rpcInitialDelayMs = [int]$rpcPolicy.InitialDelayMs
	$useRetry = [bool](Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)
	$useOptionalRetryHelper = [bool](Get-Command Invoke-WithOptionalRetry -ErrorAction SilentlyContinue)

	$invokeDesktopOperation = {
		param([scriptblock]$Operation)

		if ($useOptionalRetryHelper) {
			return Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
		}

		if ($useRetry) {
			return Invoke-WithRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
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

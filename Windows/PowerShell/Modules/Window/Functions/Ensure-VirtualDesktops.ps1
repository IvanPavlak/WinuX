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

		Sits on the Window module's seam: every count, create and remove call runs through
		Invoke-VirtualDesktopOperation (5 attempts / 250 ms initial delay), and the first
		count carries -Probe so the live RPC endpoint is verified and repaired once, up
		front, before a sequence of several desktop operations. When an operation fails
		with the RPC-unavailable family of errors (0x800706BA and friends - the state an
		Explorer restart leaves behind), the seam reconnects the session's VirtualDesktop
		COM proxies via Reset-VirtualDesktopState and retries with backoff, so the session
		heals in place instead of failing until a new shell is opened; any other error
		surfaces at once. Desktop switches go through Switch-VirtualDesktop, which confirms
		the desktop is showing. This function carries no retry or recovery block of its own.

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

	if (-not (Import-VirtualDesktopModule -Silent)) {
		Write-Error "VirtualDesktop module not found. Please install it:"
		Write-LogWarning "Install-Module -Name VirtualDesktop -Scope CurrentUser" -NoLeadingNewline
		Write-LogStep "Or visit: https://github.com/MScholtes/PSVirtualDesktop" -NoLeadingNewline
		return $false
	}

	# Every desktop-manager call goes through the operation seam, which reconnects a stale COM
	# session and retries. The first call probes the live RPC endpoint up front (-Probe): this is a
	# sequence of several desktop operations, and one preflight beats a repair inside each of them.
	$run = {
		param([scriptblock]$Operation)
		Invoke-VirtualDesktopOperation -Operation $Operation -Label 'ensuring virtual desktops' -MaxAttempts 5 -InitialDelayMs 250
	}

	try {
		$currentCount = [int](Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Label 'ensuring virtual desktops' -MaxAttempts 5 -InitialDelayMs 250 -Probe)

		Write-LogDebug "[Ensuring $Count virtual desktops exist]"
		Write-LogDebug "Existing desktop count => [$currentCount]" -Style Step
		Write-LogDebug "Required desktop count => [$Count]" -Style Warning

		if ($currentCount -lt $Count) {
			$toCreate = $Count - $currentCount
			Write-LogDebug "Creating [$toCreate] additional virtual desktop(s)..." -Style Warning

			for ($i = 0; $i -lt $toCreate; $i++) {
				[void](& $run { New-Desktop > $null })
				Write-LogDebug "Created desktop [$($currentCount + $i + 1)]" -Style Success
				Start-Sleep -Milliseconds $script:WindowModuleDelays.VirtualDesktopMs
			}

			# Verify desktops were created
			$finalCount = [int](& $run { Get-DesktopCount })
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
				while ($currentCount -gt $Count) {
					$desktopToRemove = $currentCount - 1
					[void](& $run { Remove-Desktop -Desktop $desktopToRemove -Verbose:$false -ErrorAction Stop })
					$currentCount = [int](& $run { Get-DesktopCount })
				}
				[void](Switch-VirtualDesktop -Index 0)
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
			[void](Switch-VirtualDesktop -Index $internalDesktopIndex)
			Write-LogDebug "Switched to virtual desktop [$SwitchToDesktop]"
		}

		return $true
	}
	catch {
		Write-Error "Failed to manage virtual desktops: $_"
		return $false
	}
}

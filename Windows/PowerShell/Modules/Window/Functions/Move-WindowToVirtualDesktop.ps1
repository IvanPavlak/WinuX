function Move-WindowToVirtualDesktop {
	<#
	.SYNOPSIS
		Moves a window to a specific virtual desktop.

	.DESCRIPTION
		Moves a window (identified by its handle) to the specified virtual desktop number.
		Requires the VirtualDesktop module (warns with the install command and returns $false
		without it). The current-desktop read, the desktop count, the target lookup and the
		Move-Window call all run through Invoke-VirtualDesktopOperation, so a stale COM
		session is reconnected and the call retried instead of a stale desktop count making
		every target "out of range"; a non-RPC error (a pinned or system window whose current
		desktop cannot be resolved) comes straight back and the move path is still tried.
		Note: This function uses 0-based indexing internally. Layout files use 1-based
		indexing which is converted before calling this function.

		A window already on the target desktop returns $true immediately (no COM move, no
		settle delay) - workspace windows are desktop-moved from more than one code path,
		so this is the common case. After a real move the result is verified immediately
		and then polled briefly instead of a fixed sleep. $script:LastMoveWindowToVirtualDesktopResult.Moved
		reports whether a real move was performed, so callers can skip their own settle
		delays on the fast path.

	.PARAMETER WindowHandle
		The window handle (HWND) to move.

	.PARAMETER DesktopNumber
		The desktop number (0-based index) to move the window to.

	.PARAMETER Clock
		The wait clock (New-WaitClock) the post-move verification poll reads and sleeps
		through. Defaults to a real one; tests hand in a fake.

	.EXAMPLE
		$handle = (Get-WindowHandle -ProcessName "chrome")[0].Handle
		Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0 # Moves to the first desktop

	.EXAMPLE
		Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1 # Moves to the second desktop
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$DesktopNumber,

		[Parameter()]
		[AllowNull()]
		[object]$Clock
	)

	# Tells callers whether a real move was performed (vs. the already-on-target fast path),
	# so post-move settle delays can be skipped when nothing actually moved.
	$script:LastMoveWindowToVirtualDesktopResult = @{ Moved = $false }

	if (-not (Import-VirtualDesktopModule)) {
		Write-Warning "VirtualDesktop module not found. To install it, run:"
		Write-Warning "Install-Module -Name VirtualDesktop -Scope CurrentUser"
		Write-Host "`nAlternatively, you can install it via: https://github.com/MScholtes/PSVirtualDesktop"
		return $false
	}

	# Every desktop-manager call goes through the operation seam: a stale COM session is
	# reconnected and the call retried instead of a stale desktop count making every target
	# "out of range".
	$run = {
		param([scriptblock]$Operation)
		Invoke-VirtualDesktopOperation -Operation $Operation -Label "moving a window to desktop index $DesktopNumber"
	}

	try {
		# Fast path: the window is already on the target desktop - no COM move, no settle
		# delay. Every workspace window is desktop-moved from more than one code path
		# (early-stable callback + layout pass), so this is the common case.
		try {
			$currentDesktopIndex = & $run { Get-DesktopIndex (Get-DesktopFromWindow -Hwnd $WindowHandle.ToInt64()) }
			if ($currentDesktopIndex -eq $DesktopNumber) {
				Write-Verbose "Window already on desktop index $DesktopNumber - skipping move"
				return $true
			}
		}
		catch {
			# Unresolvable current desktop (pinned/system window) - fall through to the move path.
			if (Test-RpcUnavailableError $_) { throw }
		}

		# Validate the target against the live count
		$desktopCount = [int](& $run { Get-DesktopCount })
		Write-Verbose "Found $desktopCount virtual desktop(s)"

		if ($DesktopNumber -lt 0 -or $DesktopNumber -ge $desktopCount) {
			Write-Error "Desktop number $DesktopNumber is out of range. Available desktops: 0-$($desktopCount - 1)"
			return $false
		}

		# Get the target desktop directly by its index (0-based)
		$targetDesktopObj = & $run { Get-Desktop -Index $DesktopNumber }
		if (-not $targetDesktopObj) {
			Write-Error "Could not find virtual desktop with index $DesktopNumber"
			return $false
		}

		Write-Verbose "Moving window (handle: 0x$($WindowHandle.ToString('X'))) to desktop object"
		$moveError = $null
		try {
			# Move-Window emits the Desktop object; without discarding it the function's
			# pipeline output becomes @(Desktop, $bool), which is truthy even when the
			# verification below returns $false - callers would count a failed move as moved.
			$null = & $run { Move-Window -Desktop $targetDesktopObj -Hwnd $WindowHandle.ToInt64() }
		}
		catch {
			# Capture the error but don't fail yet - the move may have landed regardless.
			$moveError = $_
		}

		# Verify immediately, then poll briefly: the COM move is effectively synchronous
		# most of the time, so a fixed post-move sleep wastes the common case, while a
		# single fixed-delay check can race on a loaded system and report a false failure.
		# The poll records the last index and error in this table (a shared object survives the
		# condition's child scope where a local would not); a failed read keeps the last index.
		$verify = @{ Index = -1; Error = $null }
		$null = Wait-Until -TimeoutMs 100 -PollIntervalMs 10 -Clock $Clock -Condition {
			try {
				$verifyDesktop = Get-DesktopFromWindow -Hwnd $WindowHandle.ToInt64()
				$verify.Index = Get-DesktopIndex $verifyDesktop
				$verify.Error = $null
			}
			catch {
				# TYPE_E_ELEMENTNOTFOUND often occurs during verification even when move succeeded
				$verify.Error = $_
			}
			return ($verify.Index -eq $DesktopNumber)
		}
		$verifyIndex = $verify.Index
		$verifyError = $verify.Error

		if ($verifyIndex -eq $DesktopNumber) {
			$script:LastMoveWindowToVirtualDesktopResult.Moved = $true
			if (Test-LogVerbose) {
				Write-Verbose "Window is now on desktop index $verifyIndex"
				Write-LogDebug "Moved window to virtual desktop [$DesktopNumber]" -Style Success
			}
			return $true
		}
		elseif ($moveError -or $verifyError) {
			# TYPE_E_ELEMENTNOTFOUND is common and often does not indicate a real failure.
			if (Test-LogVerbose) {
				$errorToReport = if ($moveError) { $moveError } else { $verifyError }
				Write-Warning "Move-WindowToVirtualDesktop encountered error (may be transient): $errorToReport"
			}
			return $false
		}
		else {
			if (Test-LogVerbose) {
				Write-Warning "Window move could not be verified. Expected desktop $DesktopNumber, found $verifyIndex"
			}
			return $false
		}
	}
	catch {
		if (Test-LogVerbose) {
			Write-Warning "Move-WindowToVirtualDesktop encountered error: $_"
		}
		return $false
	}
}

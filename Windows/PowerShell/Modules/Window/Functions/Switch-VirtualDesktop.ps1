function Switch-VirtualDesktop {
	<#
	.SYNOPSIS
		Brings a virtual desktop on screen and confirms it is showing.

	.DESCRIPTION
		Switching desktops is asynchronous and, in a long-running shell, silently unreliable: a
		Switch-Desktop against a stale COM proxy no-ops without an error. So this does what every
		caller used to do by hand - switch, poll until the current desktop IS the target, retry a
		few times, and when it still has not landed reconnect the VirtualDesktop session
		(Reset-VirtualDesktopState) and try once more. The window cache is cleared after a
		successful switch, because handles enumerated before it describe the previous desktop.

		A desktop that is already showing is reported as switched without touching the manager.

	.PARAMETER Index
		The 0-based index of the desktop to show.

	.PARAMETER TimeoutMs
		How long each attempt waits for the switch to land. Default 750.

	.PARAMETER PollIntervalMs
		Delay between checks while waiting. Default 10.

	.PARAMETER MaxAttempts
		Switch attempts before the session reset is tried. Default 3.

	.PARAMETER Clock
		The wait clock (New-WaitClock) each attempt's wait reads and sleeps through. Defaults to
		a real one; tests hand in a fake.

	.OUTPUTS
		[bool] $true when the desktop is showing, $false when it never landed. Throws only when the
		desktop manager cannot be reached at all (module missing, RPC dead after recovery).

	.EXAMPLE
		if (-not (Switch-VirtualDesktop -Index 2)) { Write-LogError "Desktop 3 did not come on screen" }
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateRange(0, 255)]
		[int]$Index,

		[Parameter()]
		[ValidateRange(0, 60000)]
		[int]$TimeoutMs = 750,

		[Parameter()]
		[ValidateRange(0, 10000)]
		[int]$PollIntervalMs = 10,

		[Parameter()]
		[ValidateRange(1, 10)]
		[int]$MaxAttempts = 3,

		[Parameter()]
		[AllowNull()]
		[object]$Clock
	)

	if (-not (Import-VirtualDesktopModule -Silent)) {
		throw "The VirtualDesktop module is not available - install it with: Install-Module -Name VirtualDesktop -Scope CurrentUser (https://github.com/MScholtes/PSVirtualDesktop)"
	}

	$isShowing = {
		# Transient COM errors are expected mid-switch; they read as "not yet".
		try { return ((Get-CurrentVirtualDesktopIndex) -eq $Index) } catch { return $false }
	}

	$waitUntilShowing = {
		Wait-Until -Condition $isShowing -TimeoutMs $TimeoutMs -PollIntervalMs $PollIntervalMs -Clock $Clock
	}

	if (& $isShowing) {
		return $true
	}

	$switched = $false
	for ($attempt = 1; $attempt -le $MaxAttempts -and -not $switched; $attempt++) {
		try {
			Invoke-VirtualDesktopOperation -Operation { $null = Switch-Desktop -Desktop $Index -ErrorAction Stop } -Label "switching to desktop index $Index"
		}
		catch {
			Write-LogDebug "  Switch to desktop index $Index failed (attempt $attempt/$MaxAttempts) => $($_.Exception.Message)" -Style Warning
		}
		$switched = & $waitUntilShowing
	}

	if (-not $switched -and (Reset-VirtualDesktopState)) {
		try {
			Invoke-VirtualDesktopOperation -Operation { $null = Switch-Desktop -Desktop $Index -ErrorAction Stop } -Label "switching to desktop index $Index after a session reset"
		}
		catch {
			Write-LogDebug "  Switch to desktop index $Index failed after the session reset => $($_.Exception.Message)" -Style Warning
		}
		$switched = & $waitUntilShowing
		if ($switched) {
			Write-LogDebug "  Desktop index $Index recovered after the VirtualDesktop session reset" -Style Warning
		}
	}

	if ($switched -and (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue)) {
		Clear-WindowCache
	}

	return $switched
}

function Ensure-DesktopVisible {
	<#
	.SYNOPSIS
		Brings a virtual desktop on screen - by index, or the one a given window lives on.

	.DESCRIPTION
		Some window content only exists while its virtual desktop is the visible one. Windows Terminal
		is the case that motivated this: it hosts its tab strip in a XAML island that is not composed
		while the desktop is off screen, so UI Automation reports the window as having no descendants
		at all - no tabs to read, no close buttons to invoke. Every UIA-based tab operation silently
		fails against a terminal parked on another desktop, which is exactly where a workspace's
		terminal lives once the layout pass has moved it.

		Unlike Focus-VirtualDesktop this does one thing: it makes a desktop visible. No window
		enumeration, no focus locking, no section title - so a caller can bring a desktop up, do its
		work, and put the view back without narrating a "focus" step it never intended.

		Returns the index of the desktop that WAS visible, so the caller can restore it by passing
		that index straight back in. A return of $null means nothing needs restoring: either the
		desktop was already the visible one, or the switch could not be made.

		The switch is confirmed with Wait-DesktopSwitch and retried through a Reset-VirtualDesktopState
		recovery pass, mirroring Focus-VirtualDesktop - a long-running shell can hold a stale
		VirtualDesktop COM proxy whose Switch-Desktop silently no-ops.

	.PARAMETER WindowHandle
		Bring up whichever desktop this window lives on.

	.PARAMETER DesktopIndex
		Bring up this 0-based desktop index. Used to restore a previously returned index.

	.OUTPUTS
		[int] the index of the desktop that was visible before the switch, or $null when no switch
		happened or it failed.

	.EXAMPLE
		$previous = Ensure-DesktopVisible -WindowHandle $terminalWindow
		$tabs = Get-WindowsTerminalTabTitles -WindowHandle $terminalWindow
		if ($null -ne $previous) { [void](Ensure-DesktopVisible -DesktopIndex $previous) }
	#>
	[CmdletBinding(DefaultParameterSetName = 'Window')]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true, ParameterSetName = 'Window')]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true, ParameterSetName = 'Index')]
		[int]$DesktopIndex
	)

	if (-not (Get-Command Switch-Desktop -ErrorAction SilentlyContinue)) {
		if (Get-Command Import-VirtualDesktopModule -ErrorAction SilentlyContinue) {
			[void](Import-VirtualDesktopModule -Silent)
		}
	}

	if (-not (Get-Command Switch-Desktop -ErrorAction SilentlyContinue)) {
		Write-LogDebug " [Ensure-DesktopVisible] VirtualDesktop module unavailable - cannot change the visible desktop" -Style Warning
		return $null
	}

	try {
		$currentIndex = Get-DesktopIndex -Desktop (Get-CurrentDesktop)

		$targetIndex = if ($PSCmdlet.ParameterSetName -eq 'Index') {
			$DesktopIndex
		}
		else {
			$windowDesktop = Get-DesktopFromWindow -Hwnd $WindowHandle
			if (-not $windowDesktop) { return $null }
			Get-DesktopIndex -Desktop $windowDesktop
		}
	}
	catch {
		Write-LogDebug " [Ensure-DesktopVisible] Could not resolve the target desktop => $($_.Exception.Message)" -Style Warning
		return $null
	}

	if ($null -eq $targetIndex -or $targetIndex -lt 0) { return $null }

	# Already showing - report "nothing to restore" so the caller does not switch back to a desktop
	# it never left.
	if ($targetIndex -eq $currentIndex) { return $null }

	$switched = $false
	for ($attempt = 1; $attempt -le 3; $attempt++) {
		try {
			$null = Switch-Desktop -Desktop $targetIndex -ErrorAction Stop
			if (Wait-DesktopSwitch -TargetDesktopIndex $targetIndex) {
				$switched = $true
				break
			}
		}
		catch {
			Write-LogDebug " [Ensure-DesktopVisible] Switch to desktop index $targetIndex failed (attempt $attempt/3) => $($_.Exception.Message)" -Style Warning
		}
	}

	if (-not $switched -and (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue)) {
		if (Reset-VirtualDesktopState) {
			try {
				$null = Switch-Desktop -Desktop $targetIndex -ErrorAction Stop
				$switched = Wait-DesktopSwitch -TargetDesktopIndex $targetIndex
			}
			catch {
				$switched = $false
			}
		}
	}

	if (-not $switched) {
		Write-LogDebug " [Ensure-DesktopVisible] Could not bring desktop index $targetIndex on screen" -Style Warning
		return $null
	}

	# Handles enumerated before the switch describe the previous desktop's composition.
	if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) {
		Clear-WindowCache
	}

	return $currentIndex
}

function Invoke-SingleZoneWindowPlacement {
	<#
	.SYNOPSIS
		Places a window directly at a single-zone layout's zone rectangle, with verification.

	.DESCRIPTION
		The deterministic DIRECT-placement primitive for windows assigned to a single-zone
		FancyZones layout (e.g. Zone = "Fullscreen" on the one-zone "Zero" grid): it calls
		Set-WindowPosition straight to the (frame-compensated) zone rectangle and verifies the
		result with Wait-WindowRect - the same geometry check the snap path and
		Confirm-WorkspaceWindowPositions use. Because it bypasses FancyZones entirely, the
		window it places is NOT registered as zoned (see Get-FancyZonesWindowAssignment), which
		is why it serves exactly one caller: Set-WorkspaceWindowLayout's simple-layout path,
		where windows sit on INVISIBLE desktops that FancyZones' own keyboard and drag paths
		cannot reach without desktop switching. The workspace flow (Snap-AllWindows) snaps
		single-zone windows through Invoke-SingleZoneWindowSnap instead, so they end up
		registered.

		Set-WindowPosition is used directly (not Resize-Windows -InsetPercent 0) because
		Get-InsetWindowBounds applies an unconditional center bias even at zero inset - the
		bias exists to keep the RELATIVE snap deterministic, which is exactly what this
		placement does not do.

		The rectangle that reaches SetWindowPos is the zone grown by the window's frame
		margins (Get-WindowFrameMargin), because SetWindowPos and the zone rectangle are not
		in the same coordinate space: SetWindowPos positions the window FRAME, which includes
		the DWM invisible resize border, while FancyZones fills a zone with the window's
		VISIBLE frame. Placing the frame at the zone rectangle therefore leaves the visible
		window inset by the border on every edge that has one - a thin strip of desktop down
		the left, right and bottom of a fullscreen window - which is the geometry a manual
		Win+Arrow then corrects. Compensating here reproduces the snap path's result exactly,
		and the margins are measured once per placement rather than per attempt, since neither
		the window's style nor its monitor changes between retries. A window with no border
		(console, borderless) measures zero and is placed at the zone rectangle unchanged.

		The window is not registered in FancyZones' app-zone-history by a plain SetWindowPos.
		That is the accepted cost of the two situations this primitive exists for: relocation
		on zone-set and display changes will skip the window, though later manual Win+Arrow
		moves still work because the required fancyzones_moveWindowsBasedOnPosition setting
		resolves zones from the window's position, not its history. Callers that can put the
		window's desktop on screen should snap through Invoke-SingleZoneWindowSnap instead.

		Retries re-issue the placement with a growing verification budget. Failures that a
		SetWindowPos cannot fix (an app enforcing a minimum/maximum size smaller than the
		zone) will not be fixed by more attempts either - the caller reports the expected vs
		actual bounds and hands the window to the workspace retry loop.

	.PARAMETER WindowHandle
		The handle of the window to place.

	.PARAMETER TargetX
		Zone left edge in physical pixels.

	.PARAMETER TargetY
		Zone top edge in physical pixels.

	.PARAMETER TargetWidth
		Zone width in physical pixels.

	.PARAMETER TargetHeight
		Zone height in physical pixels.

	.PARAMETER WindowTitle
		Window title used only for log messages.

	.PARAMETER MaxAttempts
		Maximum placement attempts before reporting failure. Default is 3, matching the
		snap path's retry count.

	.OUTPUTS
		PSCustomObject with:
		- Verified : $true once the window rect matched the frame-compensated target within tolerance
		- Attempts : how many attempts ran
		- X/Y/Width/Height : the last observed bounds ($null when the rect was never readable)

	.EXAMPLE
		$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
		$result = Invoke-SingleZoneWindowPlacement -WindowHandle $handle -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
		if ($result.Verified) { "placed" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$TargetX,

		[Parameter(Mandatory = $true)]
		[int]$TargetY,

		[Parameter(Mandatory = $true)]
		[int]$TargetWidth,

		[Parameter(Mandatory = $true)]
		[int]$TargetHeight,

		[Parameter()]
		[string]$WindowTitle = '',

		[Parameter()]
		[int]$MaxAttempts = 3
	)

	$lastWait = $null

	# Grow the zone by the window's invisible border so the VISIBLE frame lands flush with
	# the zone, the way FancyZones' own snap does. Measured once: the border depends on the
	# window's style and its monitor's DPI, neither of which changes between attempts. Zero
	# margins (borderless window, unreadable DWM bounds) leave the zone rectangle untouched.
	$margin = Get-WindowFrameMargin -WindowHandle $WindowHandle
	$placeX = $TargetX - $margin.Left
	$placeY = $TargetY - $margin.Top
	$placeWidth = $TargetWidth + $margin.Left + $margin.Right
	$placeHeight = $TargetHeight + $margin.Top + $margin.Bottom

	if ($margin.Left -or $margin.Top -or $margin.Right -or $margin.Bottom) {
		Write-LogDebug "     Frame compensation for [$WindowTitle] => L$($margin.Left) T$($margin.Top) R$($margin.Right) B$($margin.Bottom), placing at ($placeX, $placeY) [${placeWidth}x${placeHeight}]"
	}

	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		if ($attempt -gt 1) {
			Write-LogDebug "     ↻ Placement retry $attempt/$MaxAttempts for [$WindowTitle]..."
		}

		$positioned = $false
		try {
			$positioned = Set-WindowPosition -WindowHandle $WindowHandle `
				-X $placeX -Y $placeY -Width $placeWidth -Height $placeHeight
		}
		catch {
			Write-LogDebug "     ✗ Placement attempt $attempt failed for [$WindowTitle] => $_" -Style Error
			$positioned = $false
		}

		if (-not $positioned) {
			continue
		}

		# Growing budget like the snap path: apps repaint/settle asynchronously after
		# SetWindowPos, and DWM can report the pre-move rect for a few frames.
		$lastWait = Wait-WindowRect -WindowHandle $WindowHandle `
			-ExpectedX $placeX -ExpectedY $placeY `
			-ExpectedWidth $placeWidth -ExpectedHeight $placeHeight `
			-TimeoutMs (150 + (($attempt - 1) * 150))

		if ($lastWait.Verified) {
			return [PSCustomObject]@{
				Verified = $true
				Attempts = $attempt
				X        = $lastWait.X
				Y        = $lastWait.Y
				Width    = $lastWait.Width
				Height   = $lastWait.Height
			}
		}
	}

	return [PSCustomObject]@{
		Verified = $false
		Attempts = $MaxAttempts
		X        = if ($lastWait) { $lastWait.X } else { $null }
		Y        = if ($lastWait) { $lastWait.Y } else { $null }
		Width    = if ($lastWait) { $lastWait.Width } else { $null }
		Height   = if ($lastWait) { $lastWait.Height } else { $null }
	}
}

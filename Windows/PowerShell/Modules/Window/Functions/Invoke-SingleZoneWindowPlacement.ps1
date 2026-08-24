function Invoke-SingleZoneWindowPlacement {
	<#
	.SYNOPSIS
		Places a window directly at a single-zone layout's zone rectangle, with verification.

	.DESCRIPTION
		The deterministic placement primitive for windows assigned to a single-zone FancyZones
		layout (e.g. Zone = "Fullscreen" on the one-zone "Zero" grid). The regular snap path
		(Snap-AllWindows) steers FancyZones' Win+Arrow, which is a RELATIVE move: FancyZones
		decides which zone the window is in and hands it to the NEIGHBOURING zone in that
		direction. A single-zone layout has no neighbouring zone on the same monitor, so the
		move is ambiguous - with moveWindowAcrossMonitors enabled it can throw the window to
		another monitor's zone, and on a single monitor it no-ops, burning every retry plus
		the shift-drag fallback. With exactly one zone there is nothing FancyZones needs to
		arbitrate, so this helper calls Set-WindowPosition straight to the zone rectangle and
		verifies the result with Wait-WindowRect - the same geometry check the snap path and
		Confirm-WorkspaceWindowPositions use.

		Set-WindowPosition is used directly (not Resize-Windows -InsetPercent 0) because
		Get-InsetWindowBounds applies an unconditional center bias even at zero inset - the
		bias exists to keep the RELATIVE snap deterministic, which is exactly what this
		placement does not do.

		The window is not registered in FancyZones' app-zone-history by a plain SetWindowPos.
		That is harmless here: workspace verification is geometry-only, and later manual
		Win+Arrow moves still work because the required fancyzones_moveWindowsBasedOnPosition
		setting resolves zones from the window's position, not its history.

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
		- Verified : $true once the window rect matched the zone within tolerance
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

	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		if ($attempt -gt 1) {
			Write-LogDebug "     ↻ Placement retry $attempt/$MaxAttempts for [$WindowTitle]..."
		}

		$positioned = $false
		try {
			$positioned = Set-WindowPosition -WindowHandle $WindowHandle `
				-X $TargetX -Y $TargetY -Width $TargetWidth -Height $TargetHeight
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
			-ExpectedX $TargetX -ExpectedY $TargetY `
			-ExpectedWidth $TargetWidth -ExpectedHeight $TargetHeight `
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

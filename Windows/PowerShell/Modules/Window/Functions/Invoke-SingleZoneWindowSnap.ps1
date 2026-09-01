function Invoke-SingleZoneWindowSnap {
	<#
	.SYNOPSIS
		Snaps a window into a single-zone FancyZones layout: center it in the zone, Win+Up, shift-drag fallback.

	.DESCRIPTION
		The single-zone counterpart of the multi-zone keyboard-snap loop in Snap-AllWindows,
		kept deliberately simple: move the window to the middle of the zone at a DEEPER inset
		than the shared pre-snap inset, send Win+Up, verify, and fall back to shift-drag. Both
		are FancyZones' own mechanisms, so a verified snap leaves the window REGISTERED as
		zoned (assignment marker stamped, tracked by the live work area) rather than merely
		positioned - the gap a plain SetWindowPos placement leaves.

		Two single-zone-specific adjustments make the relative Win+Up deterministic here:

		- A stale FancyZones assignment is cleared first (Clear-FancyZonesWindowAssignment).
		  FancyZones' position-based Win+Arrow only considers zones the window is NOT assigned
		  to, and the marker survives every programmatic move, so a Reset-Windows leftover
		  would otherwise turn the only zone into a no-op (single monitor) or a throw to the
		  next monitor's zone (moveWindowAcrossMonitors).
		- The pre-snap position is the middle of the zone at DOUBLE the shared inset (capped
		  at 20% per side). A fullscreen zone inset only 5% still nearly fills the monitor;
		  a clearly-contained centered window gives the position-based move exactly one zone
		  to resolve to, and gives the shift-drag fallback comfortable grab points.

		Verification compares the DWM frame-compensated rectangle (Get-WindowFrameMargin) -
		the exact frame rect a FancyZones snap produces. When every attempt is exhausted the
		window is reported unverified and handed to the caller's retry, the same contract as
		the multi-zone path.

		One limitation is FancyZones' own and no snap method avoids it: app-zone-history has
		no per-window identity. The durable store FancyZones re-reads when it rebuilds a work
		area on a desktop switch is keyed by APP PATH plus monitor plus virtual desktop and
		holds one zone entry per key, and every virtual-desktop sync re-stamps the WHOLE file
		onto the desktop that is current at that moment. A workspace open creates and destroys
		desktops, so that sync fires repeatedly and keeps moving which single desktop owns a
		given application's row. For a process with windows on several desktops (Firefox) at
		most one of those desktops keeps the row; the rebuild re-seeds its window-to-zone map
		by app path, and a miss leaves the window untracked, so FancyZones' relocation on a
		later zone-set or display change moves nothing on that desktop. A single-window process
		(VS Code) is uncontested and behaves. The assignment marker and the live tracking are
		correct either way, so Win+Arrow and the current session's layout behavior are
		unaffected, and a manual Win+Arrow once the desktops have settled rewrites the row for
		that desktop.

		The window's virtual desktop must be the ACTIVE one and the window focusable -
		keyboard and drag snaps act on the visible desktop. Callers that place windows on
		invisible desktops (Set-WorkspaceWindowLayout's simple-layout path) use
		Invoke-SingleZoneWindowPlacement instead, trading registration for that ability.

	.PARAMETER WindowHandle
		The handle of the window to snap.

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
		Maximum keyboard-plus-drag attempts before reporting failure. Default is 3, matching
		the multi-zone snap path's retry count.

	.PARAMETER InsetPercent
		The shared pre-snap inset (defaults to Get-WindowInsetPercent). The pre-snap centering
		uses DOUBLE this value, capped at 0.2 per side.

	.OUTPUTS
		PSCustomObject with:
		- Verified   : $true once the window rect matched the frame-compensated zone rectangle
		- Registered : $true when the window carries FancyZones' zone assignment afterwards
		- Method     : KeyboardSnap | ShiftDrag | None
		- Attempts   : snap attempts consumed
		- X/Y/Width/Height : the last observed bounds ($null when the rect was never readable)

	.EXAMPLE
		$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
		$result = Invoke-SingleZoneWindowSnap -WindowHandle $handle -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
		if ($result.Verified) { "snapped via $($result.Method)" }
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
		[int]$MaxAttempts = 3,

		[Parameter()]
		[double]$InsetPercent = (Get-WindowInsetPercent)
	)

	# The frame rect a successful FancyZones snap produces: the zone grown by the DWM
	# invisible border. Zero margins (borderless window, unreadable DWM data) reduce this to
	# the zone rectangle itself.
	$margin = Get-WindowFrameMargin -WindowHandle $WindowHandle
	$expectedX = $TargetX - $margin.Left
	$expectedY = $TargetY - $margin.Top
	$expectedWidth = $TargetWidth + $margin.Left + $margin.Right
	$expectedHeight = $TargetHeight + $margin.Top + $margin.Bottom

	# A stale assignment excludes the only zone from FancyZones' position-based move - clear
	# it so Win+Up resolves INTO the zone the window is sitting in.
	$zoneMask = Get-FancyZonesWindowAssignment -WindowHandle $WindowHandle
	if ($zoneMask -ne 0) {
		$null = Clear-FancyZonesWindowAssignment -WindowHandle $WindowHandle
		Write-LogDebug "     Cleared stale FancyZones assignment (mask 0x$($zoneMask.ToString('X'))) for [$WindowTitle] so the keyboard snap can resolve"
	}

	# Middle of the zone, clearly contained: double the shared inset, capped at 20% per side.
	$preSnapInsetPercent = [Math]::Min(0.2, $InsetPercent * 2)

	$lastWait = $null

	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		if ($attempt -gt 1) {
			Write-LogDebug "     ↻ Snap retry $attempt/$MaxAttempts for [$WindowTitle]..."

			# The failed attempt may have stranded a modifier - clear the keyboard state
			# before injecting again.
			$null = Reset-KeyboardModifiers
		}

		# Move to the middle of the zone at the deeper inset before every keyboard attempt.
		try {
			$null = Resize-Windows `
				-WindowHandle $WindowHandle `
				-TargetX $TargetX `
				-TargetY $TargetY `
				-TargetWidth $TargetWidth `
				-TargetHeight $TargetHeight `
				-InsetPercent $preSnapInsetPercent
			Start-Sleep -Milliseconds 20
		}
		catch {
			# Continue anyway - the snap itself verifies.
		}

		# Acquire stable foreground focus immediately before injecting the snap hotkey.
		$focusSettleMs = 10 + (($attempt - 1) * 40)
		$focusAcquired = Confirm-WindowForeground -WindowHandle $WindowHandle -BaseSettleMs $focusSettleMs

		if (-not $focusAcquired) {
			Write-LogDebug "  ⚠ Could not acquire stable focus for [$WindowTitle] (attempt $attempt/$MaxAttempts)" -Style Warning
			continue
		}

		# Re-check foreground atomically right before sending input.
		if ([WindowModule.Native]::GetForegroundWindow() -ne $WindowHandle) {
			[void][WindowModule.Native]::ForceForegroundWindow($WindowHandle)
			if ([WindowModule.Native]::GetForegroundWindow() -ne $WindowHandle) {
				Write-LogDebug "  ⚠ Foreground changed before snap key injection for [$WindowTitle]" -Style Warning
				continue
			}
		}

		# Win+Up: from a centered window inside the only zone, FancyZones' position-based
		# move snaps it into that zone - assigning it and writing its history entry.
		[WindowModule.Native]::SendSnapKey($true)

		$lastWait = Wait-WindowRect -WindowHandle $WindowHandle `
			-ExpectedX $expectedX -ExpectedY $expectedY `
			-ExpectedWidth $expectedWidth -ExpectedHeight $expectedHeight `
			-TimeoutMs (200 + (($attempt - 1) * 150))

		if ($lastWait.Verified) {
			return [PSCustomObject]@{
				Verified   = $true
				Registered = ((Get-FancyZonesWindowAssignment -WindowHandle $WindowHandle) -ne 0)
				Method     = 'KeyboardSnap'
				Attempts   = $attempt
				X          = $lastWait.X
				Y          = $lastWait.Y
				Width      = $lastWait.Width
				Height     = $lastWait.Height
			}
		}

		# Keyboard snap unverified: shift-drag runs FancyZones' real drag path, which
		# registers the window just as well. Re-center first so the drag start points land
		# inside the window.
		Write-LogDebug "     ⚠ Keyboard snap unverified for [$WindowTitle], attempting shift-drag snap..." -Style Warning
		try {
			$null = Resize-Windows `
				-WindowHandle $WindowHandle `
				-TargetX $TargetX `
				-TargetY $TargetY `
				-TargetWidth $TargetWidth `
				-TargetHeight $TargetHeight `
				-InsetPercent $preSnapInsetPercent
			Start-Sleep -Milliseconds 10
		}
		catch {
			# Continue anyway
		}

		# Browser tabs always drag from the left inset to avoid tab detachment; other apps
		# rotate the start point across retries (same policy as the multi-zone snap path).
		$isBrowserWindow = [WindowModule.Native]::IsBrowserWindow($WindowHandle)
		$dragStartMode = if ($isBrowserWindow) {
			0
		}
		else {
			switch ($attempt) {
				1 { 0 }
				2 { 1 }
				default { 2 }
			}
		}

		if (Test-LogVerbose) {
			$dragStartLabel = switch ($dragStartMode) {
				0 { 'left-inset' }
				1 { 'top-center' }
				default { 'top-right-third-center' }
			}
			$windowTypeLabel = if ($isBrowserWindow) { 'browser' } else { 'non-browser' }
			Write-LogDebug "     ↳ Shift-drag start point: $dragStartLabel [$windowTypeLabel]"
		}

		$shiftDragResult = [WindowModule.Native]::ShiftDragSnap($WindowHandle, $TargetX, $TargetY, $TargetWidth, $TargetHeight, $dragStartMode)

		if ($shiftDragResult) {
			$lastWait = Wait-WindowRect -WindowHandle $WindowHandle `
				-ExpectedX $expectedX -ExpectedY $expectedY `
				-ExpectedWidth $expectedWidth -ExpectedHeight $expectedHeight `
				-TimeoutMs (250 + (($attempt - 1) * 150))

			if ($lastWait.Verified) {
				return [PSCustomObject]@{
					Verified   = $true
					Registered = ((Get-FancyZonesWindowAssignment -WindowHandle $WindowHandle) -ne 0)
					Method     = 'ShiftDrag'
					Attempts   = $attempt
					X          = $lastWait.X
					Y          = $lastWait.Y
					Width      = $lastWait.Width
					Height     = $lastWait.Height
				}
			}
		}
	}

	# Exhausted - report failure and let the caller's retry take over, exactly like the
	# multi-zone snap path.
	return [PSCustomObject]@{
		Verified   = $false
		Registered = ((Get-FancyZonesWindowAssignment -WindowHandle $WindowHandle) -ne 0)
		Method     = 'None'
		Attempts   = $MaxAttempts
		X          = if ($lastWait) { $lastWait.X } else { $null }
		Y          = if ($lastWait) { $lastWait.Y } else { $null }
		Width      = if ($lastWait) { $lastWait.Width } else { $null }
		Height     = if ($lastWait) { $lastWait.Height } else { $null }
	}
}

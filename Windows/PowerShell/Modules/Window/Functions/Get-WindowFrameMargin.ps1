function Get-WindowFrameMargin {
	<#
	.SYNOPSIS
		Measures the per-edge gap between a window's frame rectangle and the frame the user sees.

	.DESCRIPTION
		SetWindowPos and GetWindowRect both work on the window FRAME rectangle, which on a
		standard desktop window extends past the visible window by the DWM invisible resize
		border - about 7px on the left, right and bottom at 100% scaling, growing with the
		monitor's DPI. FancyZones sizes a snapped window against the VISIBLE frame instead
		(DWMWA_EXTENDED_FRAME_BOUNDS), which is why a keyboard-snapped window's GetWindowRect
		overhangs its zone while the window itself sits flush inside it. The zone rectangle
		grown by this per-edge difference is therefore the exact frame rect a FancyZones snap
		produces: Invoke-SingleZoneWindowSnap verifies its snaps against that compensated
		rectangle, and Invoke-SingleZoneWindowPlacement places directly at it.

		The margin is measured on the actual window, at call time, because it is a property of
		that window's style and its monitor's DPI rather than a constant: standard windows
		report 7/0/7/7 (left/top/right/bottom), UWP hosts report a margin on all four edges,
		and console and borderless windows report none at all.

		Every failure path returns all-zero margins rather than throwing, so a caller's
		arithmetic degrades to the uncompensated rectangle instead of breaking: either native
		read failing, a negative edge (clamped), any edge past the sanity cap (the whole
		reading is discarded - see below), and a session whose in-memory WindowNative type was
		compiled before GetExtendedFrameBounds existed, since Add-Type cannot recompile it.

		A single implausible edge discards all four rather than being clamped on its own. The
		real border is SM_CXSIZEFRAME + SM_CXPADDEDBORDER, roughly 7px at 100% scaling and
		still under 40px at the 500% ceiling, so anything past the cap means the reading came
		from a window in a state where it does not describe a border at all (cloaked,
		mid-transition). Half-trusted margins would push Wait-WindowRect into verifying a
		rectangle nothing will ever match; the uncompensated geometry is at least known-safe.

	.PARAMETER WindowHandle
		Handle of the window to measure.

	.OUTPUTS
		PSCustomObject with Left, Top, Right and Bottom margins in physical pixels. Never
		negative, and all zero when the margin could not be trusted or read.

	.EXAMPLE
		$margin = Get-WindowFrameMargin -WindowHandle $handle
		$placeWidth = $zone.Width + $margin.Left + $margin.Right

	.EXAMPLE
		Get-WindowHandle -ProcessName "firefox" | ForEach-Object { Get-WindowFrameMargin -WindowHandle $_.Handle }
		Reports the invisible border every Firefox window carries.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[IntPtr]$WindowHandle
	)

	$zeroMargin = [PSCustomObject]@{ Left = 0; Top = 0; Right = 0; Bottom = 0 }

	if ($WindowHandle -eq [IntPtr]::Zero) { return $zeroMargin }

	# Past this an edge is not describing a border any more (see the .DESCRIPTION note).
	$sanityCapPx = 50

	try {
		$frame = New-Object WindowModule.RECT
		if (-not [WindowModule.Native]::GetWindowRect($WindowHandle, [ref]$frame)) {
			Write-LogDebug "     Frame margin unreadable (no window rect) - placing without compensation"
			return $zeroMargin
		}

		$visible = New-Object WindowModule.RECT
		if (-not [WindowModule.Native]::GetExtendedFrameBounds($WindowHandle, [ref]$visible)) {
			Write-LogDebug "     Frame margin unreadable (no visible-frame bounds) - placing without compensation"
			return $zeroMargin
		}

		$left = [Math]::Max(0, $visible.Left - $frame.Left)
		$top = [Math]::Max(0, $visible.Top - $frame.Top)
		$right = [Math]::Max(0, $frame.Right - $visible.Right)
		$bottom = [Math]::Max(0, $frame.Bottom - $visible.Bottom)

		if ($left -gt $sanityCapPx -or $top -gt $sanityCapPx -or $right -gt $sanityCapPx -or $bottom -gt $sanityCapPx) {
			return $zeroMargin
		}

		return [PSCustomObject]@{
			Left   = $left
			Top    = $top
			Right  = $right
			Bottom = $bottom
		}
	}
	catch {
		# Reaching here in a long-lived session usually means its in-memory WindowNative type
		# predates GetExtendedFrameBounds, which only a new session can fix.
		Write-LogDebug "     Frame margin could not be measured ($_) - placing without compensation"
		return $zeroMargin
	}
}

function Invoke-MultiZoneWindowSnap {
	<#
	.SYNOPSIS
		Snaps a pre-positioned window into its FancyZones zone: Win+Up, shift-drag fallback, bounded attempts.

	.DESCRIPTION
		The multi-zone counterpart of Invoke-SingleZoneWindowSnap and the attempt loop that
		used to live inline in Snap-AllWindows. The window is expected to arrive already inset
		INSIDE its target zone (Set-WindowLayouts / Resize-PositionedWindows put it there), so
		FancyZones' relative Win+Up resolves to that zone. Each attempt:

		- acquires stable foreground focus (Confirm-WindowForeground) and re-checks the
		  foreground atomically right before injecting - a chord sent to the wrong window is
		  worse than no chord at all
		- sends Win+Up through the batched SendInput helper and polls the window rect
		  (Wait-WindowRect) until it matches the FULL zone rectangle, with a budget that grows
		  per attempt
		- when the keyboard snap does not verify, re-insets the window and runs FancyZones'
		  real drag path (ShiftDragSnap), rotating the drag start point across attempts for
		  non-browser windows (browsers always drag from the left inset so a tab is never torn
		  off), and polls the rect again

		Retries begin by clearing the keyboard modifier state - the failed attempt may have
		stranded one, or failed BECAUSE one was already stuck - and by re-positioning the
		window at its inset. When every attempt is exhausted the window is reported
		unverified; what happens next (zone-grid reset and a second round, or a recorded
		failure) is Snap-AllWindows' decision, not this function's.

		The window's virtual desktop must be the ACTIVE one and the window focusable.

	.PARAMETER WindowHandle
		The handle of the window to snap.

	.PARAMETER ExpectedX
		Zone left edge in physical pixels - the rect a verified snap must produce.

	.PARAMETER ExpectedY
		Zone top edge in physical pixels.

	.PARAMETER ExpectedWidth
		Zone width in physical pixels.

	.PARAMETER ExpectedHeight
		Zone height in physical pixels.

	.PARAMETER WindowTitle
		Window title used only for log messages.

	.PARAMETER MaxAttempts
		Keyboard-plus-drag attempts before reporting failure. Default is 3.

	.PARAMETER InsetPercent
		The shared pre-snap inset the window is re-positioned at between attempts and before
		the shift-drag. Defaults to Get-WindowInsetPercent.

	.OUTPUTS
		PSCustomObject with:
		- Verified : $true once the window rect matched the zone rectangle
		- Method   : KeyboardSnap | ShiftDrag | None
		- Attempts : snap attempts consumed
		- X/Y/Width/Height : the last observed bounds ($null when the rect was never readable)
		- Error    : the exception message when the final attempt threw, else $null

	.EXAMPLE
		$snap = Invoke-MultiZoneWindowSnap -WindowHandle $handle -ExpectedX 3 -ExpectedY 3 -ExpectedWidth 1717 -ExpectedHeight 1434 -WindowTitle 'Code'
		if (-not $snap.Verified) { "exhausted after $($snap.Attempts) attempts" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedX,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedY,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedWidth,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedHeight,

		[Parameter()]
		[string]$WindowTitle = '',

		[Parameter()]
		[int]$MaxAttempts = 3,

		[Parameter()]
		[double]$InsetPercent = (Get-WindowInsetPercent)
	)

	$lastWait = $null
	$lastError = $null

	# Re-inset the window between attempts and before a drag. Failures are not fatal - the
	# snap itself verifies, and a window that refuses the move fails the verification.
	$reposition = {
		param([int]$SettleMs)
		try {
			$null = Resize-Windows `
				-WindowHandle $WindowHandle `
				-TargetX $ExpectedX `
				-TargetY $ExpectedY `
				-TargetWidth $ExpectedWidth `
				-TargetHeight $ExpectedHeight `
				-InsetPercent $InsetPercent
			Start-Sleep -Milliseconds $SettleMs
		}
		catch {
			# Continue anyway
		}
	}

	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		if ($attempt -gt 1) {
			Write-LogDebug "     ↻ Retry $attempt/$MaxAttempts for [$WindowTitle]..."

			# The failed attempt itself may have stranded a modifier (or the attempt failed
			# BECAUSE one was already stuck and corrupted the combo). Clear the keyboard state
			# before injecting again so the retry starts from a known-good baseline.
			$null = Reset-KeyboardModifiers

			# The window may have been left in a bad state by the failed attempt.
			& $reposition 20
		}

		try {
			# Focus settle grows on retries; the snap verification itself polls with a budget
			# that also grows per attempt.
			$focusSettleMs = 10 + (($attempt - 1) * 40)
			$focusAcquired = Confirm-WindowForeground -WindowHandle $WindowHandle -BaseSettleMs $focusSettleMs

			if (-not $focusAcquired) {
				Write-LogDebug "  ⚠ Could not acquire stable focus for [$WindowTitle] (attempt $attempt/$MaxAttempts)" -Style Warning
				continue
			}

			# Re-check the foreground atomically right before sending input.
			if ([WindowModule.Native]::GetForegroundWindow() -ne $WindowHandle) {
				[void][WindowModule.Native]::ForceForegroundWindow($WindowHandle)
				if ([WindowModule.Native]::GetForegroundWindow() -ne $WindowHandle) {
					Write-LogDebug "  ⚠ Foreground changed before snap key injection for [$WindowTitle]" -Style Warning
					continue
				}
			}

			# Win+Up for every window: the window sits inset INSIDE its target zone, and the
			# two arrow directions are not symmetric for that state - Win+Up snaps it into the
			# zone it is sitting in, Win+Down hands it to the zone BELOW.
			[WindowModule.Native]::SendSnapKey($true)

			# Poll until FancyZones moves the window to the FULL zone position (not the inset),
			# returning as soon as the snap lands and escalating to the shift-drag only when the
			# budget is genuinely exhausted.
			$lastWait = Wait-WindowRect -WindowHandle $WindowHandle `
				-ExpectedX $ExpectedX -ExpectedY $ExpectedY `
				-ExpectedWidth $ExpectedWidth -ExpectedHeight $ExpectedHeight `
				-TimeoutMs (200 + (($attempt - 1) * 150))

			if ($lastWait.Verified) {
				if (Test-LogVerbose) {
					$retryLabel = if ($attempt -gt 1) { " (attempt $attempt)" } else { "" }
					Write-LogDebug "     ✓ Snapped [$WindowTitle] → Win+Up (verified at zone position)$retryLabel" -Style Success
				}
				return [PSCustomObject]@{
					Verified = $true
					Method   = 'KeyboardSnap'
					Attempts = $attempt
					X        = $lastWait.X
					Y        = $lastWait.Y
					Width    = $lastWait.Width
					Height   = $lastWait.Height
					Error    = $null
				}
			}

			# Keyboard snap unverified: FancyZones' real drag path registers the window just as
			# well. Re-inset first so the drag start points land inside the window.
			Write-LogDebug "     ⚠ Keyboard snap unverified for [$WindowTitle], attempting shift-drag snap..." -Style Warning
			& $reposition 10

			# Browser tabs always drag from the left inset to avoid tab detachment; other apps
			# rotate the start point across retries.
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

			$shiftDragResult = [WindowModule.Native]::ShiftDragSnap($WindowHandle, $ExpectedX, $ExpectedY, $ExpectedWidth, $ExpectedHeight, $dragStartMode)

			if ($shiftDragResult) {
				$lastWait = Wait-WindowRect -WindowHandle $WindowHandle `
					-ExpectedX $ExpectedX -ExpectedY $ExpectedY `
					-ExpectedWidth $ExpectedWidth -ExpectedHeight $ExpectedHeight `
					-TimeoutMs (250 + (($attempt - 1) * 150))

				if ($lastWait.Verified) {
					if (Test-LogVerbose) {
						$retryLabel = if ($attempt -gt 1) { " (attempt $attempt)" } else { "" }
						Write-LogDebug "     ✓ Snapped [$WindowTitle] → Shift+Drag (verified at zone position)$retryLabel" -Style Success
					}
					return [PSCustomObject]@{
						Verified = $true
						Method   = 'ShiftDrag'
						Attempts = $attempt
						X        = $lastWait.X
						Y        = $lastWait.Y
						Width    = $lastWait.Width
						Height   = $lastWait.Height
						Error    = $null
					}
				}
			}
		}
		catch {
			$lastError = "$_"
			if ($attempt -lt $MaxAttempts -and (Test-LogVerbose)) {
				Write-Warning "`n  ✗ Failed to snap [$WindowTitle] (attempt $attempt) => $_"
			}
		}
	}

	# Exhausted. The caller decides whether to reset the zone grid and try once more or to
	# record the failure.
	return [PSCustomObject]@{
		Verified = $false
		Method   = 'None'
		Attempts = $MaxAttempts
		X        = if ($lastWait) { $lastWait.X } else { $null }
		Y        = if ($lastWait) { $lastWait.Y } else { $null }
		Width    = if ($lastWait) { $lastWait.Width } else { $null }
		Height   = if ($lastWait) { $lastWait.Height } else { $null }
		Error    = $lastError
	}
}

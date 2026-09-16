function Invoke-ClearAndFastfetch {
	<#
	.SYNOPSIS
		Clears the terminal screen and displays the fastfetch system info panel,
		shrinking the font step by step until the panel fits the window.

	.DESCRIPTION
		Runs `Clear-Host` then `fastfetch`. Alias: c

		When running inside Windows Terminal, the function first measures how large
		the fastfetch panel will be by capturing its output (this renders nothing).
		In pipe mode fastfetch emits one line per visual row, so the captured line
		count is the panel height and the longest captured line is its width.

		The measuring run invokes the fastfetch BINARY rather than the `fastfetch`
		command name, so a profile-defined `fastfetch` function cannot distort the
		measurement with a decoration that has no measurable width - an inline-image
		logo is a single enormous line. The displaying run at the end goes through the
		command name as usual, so such a wrapper still decorates what you see.

		It then sends Ctrl+0 ("reset font size") so the panel is always judged
		against - and returns to - the default font. While Test-FastfetchPanelOverflow
		says the panel still overflows the window, it sends Ctrl+Minus ("decrease font
		size") one step at a time, waiting for the terminal to reflow after each step,
		until the panel fits, MaxShrinkSteps steps have been taken, or the terminal
		stops changing size (its minimum font). Resetting first makes the result
		deterministic and avoids oscillating between sizes on repeated calls: the font
		ends at the default whenever the panel fits, and at the smallest number of steps
		below the default that makes it fit when it does not. No per-machine value is
		needed - a small laptop display, a high DPI scale, a wide fastfetch configuration
		and a tall one are all absorbed by the same loop.

		Each keystroke is followed by Wait-ConsoleReflow, which polls the window size
		until it changes or ReflowTimeoutMilliseconds passes. A fixed sleep was the one
		flaky part of the earlier design - a slow machine read the pre-reflow size and
		misjudged the fit. The one wait that can run to the timeout is the reset when the
		font is already at the default, because nothing changes; that is the price of not
		knowing the font size beforehand.

		The three knobs - MaxShrinkSteps, ReflowTimeoutMilliseconds, PromptReserve - come
		from the FastfetchAutoFit configuration section through
		Resolve-FastfetchAutoFitSettings; an explicit parameter on this call overrides the
		configured value for that one call. The base ships 10 / 10 / 1.

		Because measuring and displaying are separate steps, `fastfetch` runs twice
		when auto-fit is active. Use -NoResize to keep the original single-run
		clear + fastfetch behavior.

		Auto-fit is skipped automatically outside Windows Terminal (where the
		Ctrl+0 / Ctrl+Minus bindings may not exist) and in non-interactive hosts
		that have no console window. Any failure while measuring or sending the
		keystrokes degrades gracefully to the plain clear + fastfetch behavior.

	.PARAMETER NoResize
		Skip auto-fit and run the plain clear + fastfetch once.

	.PARAMETER PromptReserve
		Rows to keep free below the panel for the upcoming prompt when deciding whether
		the panel overflows vertically. Overrides FastfetchAutoFit.PromptReserve for this
		call.

	.PARAMETER MaxShrinkSteps
		Upper bound on the number of Ctrl+Minus steps taken below the default font.
		Overrides FastfetchAutoFit.MaxShrinkSteps for this call. 0 resets the font to the
		default and never shrinks, which is useful to see whether the panel fits at all at
		the default size.

	.PARAMETER ReflowTimeoutMilliseconds
		How long to wait for the window size to change after each keystroke before
		assuming the terminal is not going to reflow. Overrides
		FastfetchAutoFit.ReflowTimeoutMilliseconds for this call.

	.EXAMPLE
		Invoke-ClearAndFastfetch
		Clears the terminal and shows the system info panel, shrinking the font as
		many steps as it takes (up to the configured cap) for the panel to fit.

	.EXAMPLE
		Invoke-ClearAndFastfetch -NoResize
		Clears the terminal and shows the panel without ever resizing.

	.EXAMPLE
		Invoke-ClearAndFastfetch -MaxShrinkSteps 0
		Resets the font to the default and shows the panel as it is, shrinking nothing.
	#>
	[CmdletBinding()]
	param(
		[switch]$NoResize,

		[AllowNull()]
		[nullable[int]]$PromptReserve,

		[AllowNull()]
		[nullable[int]]$MaxShrinkSteps,

		[AllowNull()]
		[nullable[int]]$ReflowTimeoutMilliseconds
	)

	# The Ctrl+Minus "decrease font size" binding is Windows Terminal specific, so
	# only attempt auto-fit when running inside it ($env:WT_SESSION is set there).
	$canResize = (-not $NoResize) -and [bool]$env:WT_SESSION

	if ($canResize) {
		try {
			# Configuration beats defaults, an explicit parameter beats both - but only the
			# parameters actually passed, so an unbound one leaves the configured value alone.
			$overrides = @{}
			foreach ($name in "PromptReserve", "MaxShrinkSteps", "ReflowTimeoutMilliseconds") {
				if ($PSBoundParameters.ContainsKey($name)) { $overrides[$name] = $PSBoundParameters[$name] }
			}
			$settings = Resolve-FastfetchAutoFitSettings @overrides

			# Probe the console first; this throws in non-interactive hosts (no
			# window), where sending font keystrokes would be pointless or harmful.
			$window = Get-ConsoleWindowSize

			# Capture (not display) the panel. Redirected output puts fastfetch in
			# pipe mode: one line per visual row, no color/cursor escape sequences,
			# so the line count is the height and the longest line is the width.
			# Panel size is font-independent, so it can be measured before resizing.
			#
			# Measure with the BINARY rather than with whatever `fastfetch` currently
			# resolves to. A profile is free to define a `fastfetch` function that
			# decorates the panel, and a decoration can be unmeasurable: an inline-image
			# logo is a single enormous line, so a 50KB sixel would read as a
			# 50,000-column panel and shrink the font on every call. The binary renders
			# the panel the configuration describes, which is the geometry being judged -
			# and a wrapper that swaps the logo for an image of the same cell block
			# produces exactly that geometry anyway.
			$fastfetchExe = Get-Command -Name fastfetch -CommandType Application -ErrorAction SilentlyContinue |
				Select-Object -First 1
			$captured = if ($fastfetchExe) { @(& $fastfetchExe.Source 2>$null) } else { @(fastfetch 2>$null) }
			$panelHeight = $captured.Count
			$panelWidth = ($captured | Measure-Object -Property Length -Maximum).Maximum
			if (-not $panelWidth) { $panelWidth = 0 }

			# Reset to the default font first so overflow is judged against the
			# default size and `c` always returns to that baseline when it fits.
			Send-TerminalFontKey -Action Reset
			$window = Wait-ConsoleReflow -Before $window -TimeoutMilliseconds $settings.ReflowTimeoutMilliseconds
			$defaultWindow = $window

			# Shrink one step at a time, re-reading the window after each, until the
			# panel fits or the cap is hit. A step that leaves the window unchanged
			# means the terminal is at its minimum font and cannot shrink further.
			$steps = 0
			while ($steps -lt $settings.MaxShrinkSteps -and
				(Test-FastfetchPanelOverflow -PanelWidth $panelWidth -PanelHeight $panelHeight `
					-WindowWidth $window.Width -WindowHeight $window.Height -PromptReserve $settings.PromptReserve)) {

				Send-TerminalFontKey -Action Decrease
				$steps++

				$after = Wait-ConsoleReflow -Before $window -TimeoutMilliseconds $settings.ReflowTimeoutMilliseconds
				if ($after.Width -eq $window.Width -and $after.Height -eq $window.Height) {
					Write-LogDebug "[Invoke-ClearAndFastfetch] window still $($window.Width)x$($window.Height) after Ctrl+Minus - the terminal cannot shrink further"
					break
				}
				$window = $after
			}

			if (Test-LogVerbose) {
				$fits = -not (Test-FastfetchPanelOverflow -PanelWidth $panelWidth -PanelHeight $panelHeight `
						-WindowWidth $window.Width -WindowHeight $window.Height -PromptReserve $settings.PromptReserve)
				$outcome = if ($fits) { "fits" } else { "still overflows" }
				Write-LogDebug "[Invoke-ClearAndFastfetch] panel ${panelWidth}x${panelHeight}, default window $($defaultWindow.Width)x$($defaultWindow.Height), $steps of $($settings.MaxShrinkSteps) Ctrl+Minus step(s) => window $($window.Width)x$($window.Height), panel $outcome"
			}
		}
		catch {
			Write-LogDebug " [Invoke-ClearAndFastfetch] auto-fit skipped => $($_.Exception.Message)" -Style Warning
		}
	}

	Clear-Host
	fastfetch
}

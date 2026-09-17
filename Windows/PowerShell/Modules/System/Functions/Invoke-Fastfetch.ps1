function Invoke-Fastfetch {
	<#
	.SYNOPSIS
		Displays the fastfetch system info panel, shrinking the font step by step until the panel
		fits the window - the second step of Show-TerminalGreeting.

	.DESCRIPTION
		Runs `fastfetch`. It does NOT clear the screen; Invoke-Clear is the step that does, so each
		part of the greeting can be switched off on its own.

		When running inside Windows Terminal, the function first measures how large the fastfetch
		panel will be by capturing its output (this renders nothing). In pipe mode fastfetch emits
		one line per visual row, so the captured line count is the panel height and the longest
		captured line is its width.

		The measuring run invokes the fastfetch BINARY rather than the `fastfetch` command name, so
		a profile-defined `fastfetch` function cannot distort the measurement with a decoration that
		has no measurable width - an inline-image logo is a single enormous line. The displaying run
		at the end goes through the command name as usual, so such a wrapper still decorates what
		you see.

		It then sends Ctrl+0 ("reset font size") so the panel is always judged against - and returns
		to - the default font. While Test-FastfetchPanelOverflow says the panel still overflows the
		window, it sends Ctrl+Minus ("decrease font size") one step at a time, waiting for the
		terminal to reflow after each step, until the panel fits, MaxShrinkSteps steps have been
		taken, or the terminal stops changing size (its minimum font). Resetting first makes the
		result deterministic and avoids oscillating between sizes on repeated calls: the font ends
		at the default whenever the panel fits, and at the smallest number of steps below the
		default that makes it fit when it does not. No per-machine value is needed - a small laptop
		display, a high DPI scale, a wide fastfetch configuration and a tall one are all absorbed by
		the same loop.

		-ExtraRows adds rows to the height the panel is judged by, which is how the greeting fits
		BOTH panels at once: Show-TerminalGreeting measures onefetch first and passes its row count
		here, so the font is chosen for fastfetch plus onefetch together rather than for fastfetch
		alone - otherwise the fit succeeds and onefetch then scrolls the panel off the top.

		Each keystroke is followed by Wait-ConsoleReflow, which polls the window size until it
		changes or ReflowTimeoutMilliseconds passes. A fixed sleep was the one flaky part of the
		earlier design - a slow machine read the pre-reflow size and misjudged the fit. The one wait
		that can run to the timeout is the reset when the font is already at the default, because
		nothing changes; that is the price of not knowing the font size beforehand.

		The knobs - Enabled, MaxShrinkSteps, ReflowTimeoutMilliseconds, PromptReserve - come from
		the TerminalGreeting.Fastfetch.AutoFit configuration section through
		Resolve-TerminalGreetingSettings; an explicit parameter on this call overrides the
		configured value for that one call. The base ships auto-fit on, at 10 / 10 / 1.

		Because measuring and displaying are separate steps, `fastfetch` runs twice when auto-fit is
		active. Use -NoResize (or TerminalGreeting.Fastfetch.AutoFit.Enabled = $false) to keep the
		plain single-run behavior.

		Auto-fit is skipped automatically outside Windows Terminal (where the Ctrl+0 / Ctrl+Minus
		bindings may not exist) and in non-interactive hosts that have no console window. Any
		failure while measuring or sending the keystrokes degrades gracefully to a plain single run.
		A machine without fastfetch installed is a silent no-op with one debug line, so a shell on a
		freshly cloned machine starts without an error at the prompt.

	.PARAMETER NoResize
		Skip auto-fit and run fastfetch once.

	.PARAMETER ExtraRows
		Rows to add to the measured panel height when deciding whether it overflows - the height of
		whatever will be printed below it. Show-TerminalGreeting passes onefetch's row count here.

	.PARAMETER PromptReserve
		Rows to keep free below the panel for the upcoming prompt when deciding whether the panel
		overflows vertically. Overrides TerminalGreeting.Fastfetch.AutoFit.PromptReserve for this
		call.

	.PARAMETER MaxShrinkSteps
		Upper bound on the number of Ctrl+Minus steps taken below the default font. Overrides
		TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps for this call. 0 resets the font to the
		default and never shrinks, which is useful to see whether the panel fits at all at the
		default size.

	.PARAMETER ReflowTimeoutMilliseconds
		How long to wait for the window size to change after each keystroke before assuming the
		terminal is not going to reflow. Overrides
		TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds for this call.

	.PARAMETER Settings
		The resolved greeting settings from Resolve-TerminalGreetingSettings. Show-TerminalGreeting
		resolves once and passes the tree down; omitted, this function resolves for itself, so it is
		usable on its own.

	.EXAMPLE
		Invoke-Fastfetch
		Shows the system info panel, shrinking the font as many steps as it takes (up to the
		configured cap) for the panel to fit.

	.EXAMPLE
		Invoke-Fastfetch -NoResize
		Shows the panel without ever resizing.

	.EXAMPLE
		Invoke-Fastfetch -MaxShrinkSteps 0
		Resets the font to the default and shows the panel as it is, shrinking nothing.

	.EXAMPLE
		Invoke-Fastfetch -ExtraRows 12
		Fits the panel into the window with twelve rows left free below it.
	#>
	[CmdletBinding()]
	param(
		[switch]$NoResize,

		[ValidateRange(0, [int]::MaxValue)]
		[int]$ExtraRows = 0,

		[AllowNull()]
		[nullable[int]]$PromptReserve,

		[AllowNull()]
		[nullable[int]]$MaxShrinkSteps,

		[AllowNull()]
		[nullable[int]]$ReflowTimeoutMilliseconds,

		[AllowNull()]
		[psobject]$Settings
	)

	if (-not $Settings) {
		# Configuration beats defaults, an explicit parameter beats both - but only the parameters
		# actually passed, so an unbound one leaves the configured value alone.
		$overrides = @{}
		foreach ($name in "PromptReserve", "MaxShrinkSteps", "ReflowTimeoutMilliseconds") {
			if ($PSBoundParameters.ContainsKey($name)) { $overrides[$name] = $PSBoundParameters[$name] }
		}
		$Settings = Resolve-TerminalGreetingSettings @overrides
	}

	if (-not $Settings.Fastfetch.Enabled) {
		Write-LogDebug "[Invoke-Fastfetch] skipped => TerminalGreeting.Fastfetch.Enabled is false"
		return
	}

	# Nothing to run and nothing to measure on a machine where fastfetch is not installed yet.
	if (-not (Get-Command -Name fastfetch -ErrorAction SilentlyContinue)) {
		Write-LogDebug "[Invoke-Fastfetch] skipped => fastfetch is not installed"
		return
	}

	$autoFit = $Settings.Fastfetch.AutoFit

	# The Ctrl+Minus "decrease font size" binding is Windows Terminal specific, so only attempt
	# auto-fit when running inside it ($env:WT_SESSION is set there).
	$canResize = (-not $NoResize) -and $autoFit.Enabled -and [bool]$env:WT_SESSION

	if ($canResize) {
		try {
			# Probe the console first; this throws in non-interactive hosts (no window), where
			# sending font keystrokes would be pointless or harmful.
			$window = Get-ConsoleWindowSize

			# Capture (not display) the panel. Redirected output puts fastfetch in pipe mode: one
			# line per visual row, no color/cursor escape sequences, so the line count is the height
			# and the longest line is the width. Panel size is font-independent, so it can be
			# measured before resizing.
			#
			# Measure with the BINARY rather than with whatever `fastfetch` currently resolves to. A
			# profile is free to define a `fastfetch` function that decorates the panel, and a
			# decoration can be unmeasurable: an inline-image logo is a single enormous line, so a
			# 50KB sixel would read as a 50,000-column panel and shrink the font on every call. The
			# binary renders the panel the configuration describes, which is the geometry being
			# judged - and a wrapper that swaps the logo for an image of the same cell block
			# produces exactly that geometry anyway.
			$fastfetchExe = Get-Command -Name fastfetch -CommandType Application -ErrorAction SilentlyContinue |
				Select-Object -First 1
			$captured = if ($fastfetchExe) { @(& $fastfetchExe.Source 2>$null) } else { @(fastfetch 2>$null) }
			$panelHeight = $captured.Count + $ExtraRows
			$panelWidth = ($captured | Measure-Object -Property Length -Maximum).Maximum
			if (-not $panelWidth) { $panelWidth = 0 }

			# Reset to the default font first so overflow is judged against the default size and the
			# greeting always returns to that baseline when it fits.
			Send-TerminalFontKey -Action Reset
			$window = Wait-ConsoleReflow -Before $window -TimeoutMilliseconds $autoFit.ReflowTimeoutMilliseconds
			$defaultWindow = $window

			# Shrink one step at a time, re-reading the window after each, until the panel fits or
			# the cap is hit. A step that leaves the window unchanged means the terminal is at its
			# minimum font and cannot shrink further.
			$steps = 0
			while ($steps -lt $autoFit.MaxShrinkSteps -and
				(Test-FastfetchPanelOverflow -PanelWidth $panelWidth -PanelHeight $panelHeight `
					-WindowWidth $window.Width -WindowHeight $window.Height -PromptReserve $autoFit.PromptReserve)) {

				Send-TerminalFontKey -Action Decrease
				$steps++

				$after = Wait-ConsoleReflow -Before $window -TimeoutMilliseconds $autoFit.ReflowTimeoutMilliseconds
				if ($after.Width -eq $window.Width -and $after.Height -eq $window.Height) {
					Write-LogDebug "[Invoke-Fastfetch] window still $($window.Width)x$($window.Height) after Ctrl+Minus - the terminal cannot shrink further"
					break
				}
				$window = $after
			}

			if (Test-LogVerbose) {
				$fits = -not (Test-FastfetchPanelOverflow -PanelWidth $panelWidth -PanelHeight $panelHeight `
						-WindowWidth $window.Width -WindowHeight $window.Height -PromptReserve $autoFit.PromptReserve)
				$outcome = if ($fits) { "fits" } else { "still overflows" }
				$budget = if ($ExtraRows -gt 0) { " (including $ExtraRows extra row(s))" } else { "" }
				Write-LogDebug "[Invoke-Fastfetch] panel ${panelWidth}x${panelHeight}$budget, default window $($defaultWindow.Width)x$($defaultWindow.Height), $steps of $($autoFit.MaxShrinkSteps) Ctrl+Minus step(s) => window $($window.Width)x$($window.Height), panel $outcome"
			}
		}
		catch {
			Write-LogDebug " [Invoke-Fastfetch] auto-fit skipped => $($_.Exception.Message)" -Style Warning
		}
	}

	fastfetch
}

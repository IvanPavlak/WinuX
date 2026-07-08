function Invoke-ClearAndFastfetch {
	<#
	.SYNOPSIS
		Clears the terminal screen and displays the fastfetch system info panel,
		shrinking the font once if the panel does not fit the window.

	.DESCRIPTION
		Runs `Clear-Host` then `fastfetch`. Alias: c

		When running inside Windows Terminal, the function first measures how large
		the fastfetch panel will be by capturing its output (this renders nothing).
		In pipe mode fastfetch emits one line per visual row, so the captured line
		count is the panel height and the longest captured line is its width.

		It then sends Ctrl+0 ("reset font size") so the panel is always judged
		against - and returns to - the default font. If the panel still overflows
		the window at the default size, it sends a single Ctrl+Minus ("decrease
		font size") keystroke so the panel fits. Resetting first makes the result
		deterministic and avoids oscillating between sizes on repeated calls: the
		font ends at the default whenever the panel fits, and one step below the
		default when it does not.

		Because measuring and displaying are separate steps, `fastfetch` runs twice
		when auto-fit is active. Use -NoResize to keep the original single-run
		clear + fastfetch behavior.

		Auto-fit is skipped automatically outside Windows Terminal (where the
		Ctrl+0 / Ctrl+Minus bindings may not exist) and in non-interactive hosts
		that have no console window. Any failure while measuring or sending the
		keystrokes degrades gracefully to the plain clear + fastfetch behavior.

	.PARAMETER NoResize
		Skip the auto-fit behavior; only clear the screen and run fastfetch once.

	.PARAMETER PromptReserve
		Number of rows to keep free below the panel for the upcoming prompt when
		deciding whether the panel overflows vertically. Default 1.

	.EXAMPLE
		Invoke-ClearAndFastfetch
		Clears the terminal and shows the system info panel, shrinking the font
		once if it does not fit the window.

	.EXAMPLE
		Invoke-ClearAndFastfetch -NoResize
		Clears the terminal and shows the panel without ever resizing.
	#>
	[CmdletBinding()]
	param(
		[switch]$NoResize,

		[int]$PromptReserve = 1
	)

	# The Ctrl+Minus "decrease font size" binding is Windows Terminal specific, so
	# only attempt auto-fit when running inside it ($env:WT_SESSION is set there).
	$canResize = (-not $NoResize) -and [bool]$env:WT_SESSION

	if ($canResize) {
		try {
			# Probe the console first; this throws in non-interactive hosts (no
			# window), where sending font keystrokes would be pointless or harmful.
			[void][Console]::WindowHeight

			# Capture (not display) the panel. Redirected output puts fastfetch in
			# pipe mode: one line per visual row, no color/cursor escape sequences,
			# so the line count is the height and the longest line is the width.
			# Panel size is font-independent, so it can be measured before resizing.
			$captured = @(fastfetch 2>$null)
			$panelHeight = $captured.Count
			$panelWidth = ($captured | Measure-Object -Property Length -Maximum).Maximum
			if (-not $panelWidth) { $panelWidth = 0 }

			Add-Type -AssemblyName System.Windows.Forms

			# Reset to the default font first so overflow is judged against the
			# default size and `c` always returns to that baseline when it fits.
			# The brief pause lets Windows Terminal reflow before we read the size.
			[System.Windows.Forms.SendKeys]::SendWait("^0")
			Start-Sleep -Milliseconds 150

			$windowHeight = [Console]::WindowHeight
			$windowWidth = [Console]::WindowWidth

			$overflowsHeight = $panelHeight -gt ($windowHeight - 1 - $PromptReserve)
			$overflowsWidth = $panelWidth -gt $windowWidth
			$overflows = $overflowsHeight -or $overflowsWidth

			if (Test-LogVerbose) {
				$action = if ($overflows) { "Ctrl+Minus (shrink)" } else { "Ctrl+0 only (default)" }
				Write-LogDebug "[Invoke-ClearAndFastfetch] panel ${panelWidth}x${panelHeight}, default window ${windowWidth}x${windowHeight}, overflow: $overflows => $action"
			}

			if ($overflows) {
				# Shrink one step below the default and let it reflow before render.
				[System.Windows.Forms.SendKeys]::SendWait("^-")
				Start-Sleep -Milliseconds 150
			}
		}
		catch {
			Write-LogDebug " [Invoke-ClearAndFastfetch] auto-fit skipped => $($_.Exception.Message)" -Style Warning
		}
	}

	Clear-Host
	fastfetch
}

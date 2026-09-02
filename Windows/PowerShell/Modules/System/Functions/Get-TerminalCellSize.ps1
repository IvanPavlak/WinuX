function Get-TerminalCellSize {
	<#
	.SYNOPSIS
		Reports the pixel size of one character cell, by asking the terminal itself.

	.DESCRIPTION
		Sends the XTWINOPS "report cell size" query (`CSI 16 t`) and parses the
		`CSI 6 ; height ; width t` reply, returning the width and height of a single character
		cell in pixels.

		Nothing else can answer this question. A terminal image protocol - sixel, the kitty
		graphics protocol, OSC 1337 inline images - places an image sized in PIXELS into a grid
		measured in CELLS, so the encoder has to know the conversion factor or the image lands on
		a fractional number of cells and overlaps whatever is drawn beside it. The query is the
		only portable source of that factor; there is no environment variable and no console API
		that reports it correctly under a modern terminal.

		Windows Terminal answers since 1.22.2362.0, as do WezTerm, xterm and mlterm. Everything
		else stays silent, costs the timeout once, and yields $null - which callers treat as
		"no image, use the text logo" rather than as an error.

		This function exists because fastfetch cannot do the same thing on Windows. Its
		getCharacterPixelDimensions() has two implementations, and the Windows one calls
		GetCurrentConsoleFontEx(), which its own source notes "only works for ConHost"; the
		escape-sequence path is compiled only on Unix. Under Windows Terminal the call fails and
		EVERY scaling image logo type - sixel, chafa, kitty, iterm - degrades to a placeholder
		block of slashes. Get-FastfetchLogoArgument closes that gap with this measurement.

		The reply is read from the console input buffer, so keystrokes typed during the round trip
		(a millisecond or so on a terminal that answers) are discarded along with any other
		unrecognized input. Returns $null - never throws - when the host has no console, when
		input or output is redirected (there is no terminal on the other end to answer), or when
		no reply arrives before the timeout.

	.PARAMETER TimeoutMilliseconds
		How long to wait for the reply before giving up. Default 200, which is generous for a
		local terminal and short enough to be unnoticeable when nothing answers.

	.EXAMPLE
		Get-TerminalCellSize
		Returns an object like Width=10, Height=20 under Windows Terminal, or $null elsewhere.

	.EXAMPLE
		$cell = Get-TerminalCellSize
		if ($cell) { $pixels = 36 * $cell.Width }
		Converts a 36-cell logo width into the pixel width an image has to be encoded at.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param(
		[ValidateRange(1, 5000)]
		[int]$TimeoutMilliseconds = 200
	)

	# No terminal on the other end means nothing will ever answer. Both directions matter: a
	# redirected stdout never carries the query out, a redirected stdin never carries the reply in.
	try {
		if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
			Write-LogDebug "[Get-TerminalCellSize] console redirected - cell size unavailable"
			return $null
		}

		# Throws in hosts that have no console window at all (automation, some IDE hosts).
		[void][Console]::KeyAvailable
	}
	catch {
		Write-LogDebug "[Get-TerminalCellSize] no interactive console => $($_.Exception.Message)"
		return $null
	}

	try {
		[Console]::Write("$([char]27)[16t")

		# Collect whatever arrives and match the reply out of it rather than assuming the buffer
		# holds nothing else. Anything that is not part of the reply is dropped; the alternative -
		# draining the buffer before querying - would swallow input the user had already typed.
		$reply = [Text.StringBuilder]::new()
		$timer = [Diagnostics.Stopwatch]::StartNew()

		while ($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
			if ([Console]::KeyAvailable) {
				[void]$reply.Append([Console]::ReadKey($true).KeyChar)

				# 't' terminates the report; check on it rather than on every character.
				if ($reply.ToString().EndsWith("t")) { break }
			}
			else {
				[Threading.Thread]::Sleep(1)
			}
		}

		# CSI 6 ; <height> ; <width> t - height first, which is easy to transpose.
		if ($reply.ToString() -match '6;(\d+);(\d+)t') {
			$size = [pscustomobject]@{
				Width  = [int]$Matches[2]
				Height = [int]$Matches[1]
			}

			# A terminal that reports a degenerate cell is as useless as one that reports nothing.
			if ($size.Width -lt 1 -or $size.Height -lt 1) {
				Write-LogDebug "[Get-TerminalCellSize] implausible cell size [$($size.Width)x$($size.Height)] - discarded"
				return $null
			}

			Write-LogDebug "[Get-TerminalCellSize] cell size [$($size.Width)x$($size.Height)] px after $($timer.ElapsedMilliseconds)ms"
			return $size
		}

		Write-LogDebug "[Get-TerminalCellSize] no CSI 16 t reply within ${TimeoutMilliseconds}ms - terminal does not report cell size"
		return $null
	}
	catch {
		Write-LogDebug "[Get-TerminalCellSize] cell size query failed => $($_.Exception.Message)" -Style Warning
		return $null
	}
}

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

		The reply is read from the console input buffer, and that buffer is not necessarily empty.
		A Windows Terminal tab opened with Win+<number> accepts keystrokes long before the profile
		runs, so anything typed while the tab was still loading is queued in front of the reply.
		The function therefore DRAINS the buffer before it sends the query - the typed-ahead
		characters are discarded, and the debug log records how many - and then reads until the
		complete `CSI 6 ; height ; width t` reply has arrived, never stopping early on a character
		that merely happens to be a `t`. Keystrokes that land during the round trip itself (a
		millisecond or so on a terminal that answers) are discarded the same way. Without the
		drain and the full-reply match, typing `github` into a loading tab made the read stop at
		`git`, the measurement fail, the text logo appear instead of the image, and the real reply
		spill onto the prompt as `hub[6;20;10t`.

		Returns $null - never throws - when the host has no console, when input or output is
		redirected (there is no terminal on the other end to answer), or when no reply arrives
		before the timeout.

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
		# Whatever is already queued was typed before the query and can only get in the way: the
		# reply is appended BEHIND it, and a stray 't' in the middle of a word would end the read
		# before the reply had even arrived. Discarding typed-ahead input is the deliberate trade -
		# the alternative is the reply itself leaking onto the prompt as visible garbage.
		$discarded = 0
		while ([Console]::KeyAvailable) {
			[void][Console]::ReadKey($true)
			$discarded++
		}

		if ($discarded -gt 0) {
			Write-LogDebug "[Get-TerminalCellSize] discarded $discarded queued keystroke(s) typed before the terminal was ready"
		}

		[Console]::Write("$([char]27)[16t")

		# Collect whatever arrives and read until the COMPLETE reply is in the buffer. The
		# terminator alone is not enough - a keystroke that lands mid-round-trip can be a 't' too -
		# so the whole `CSI 6 ; height ; width t` shape is what ends the read.
		$reply = [Text.StringBuilder]::new()
		$timer = [Diagnostics.Stopwatch]::StartNew()

		while ($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
			if ([Console]::KeyAvailable) {
				$key = [Console]::ReadKey($true).KeyChar
				[void]$reply.Append($key)

				# Only a 't' can complete the report; parse on those rather than on every character.
				if ($key -eq 't' -and (Test-TerminalCellSizeReply -Text $reply.ToString())) { break }
			}
			else {
				[Threading.Thread]::Sleep(1)
			}
		}

		$size = ConvertFrom-TerminalCellSizeReply -Text $reply.ToString()

		if ($size) {
			Write-LogDebug "[Get-TerminalCellSize] cell size [$($size.Width)x$($size.Height)] px after $($timer.ElapsedMilliseconds)ms"
			return $size
		}

		if (Test-TerminalCellSizeReply -Text $reply.ToString()) {
			# A terminal that reports a degenerate cell is as useless as one that reports nothing.
			Write-LogDebug "[Get-TerminalCellSize] implausible cell size in reply [$($reply.ToString() -replace '\e', 'ESC')] - discarded"
			return $null
		}

		Write-LogDebug "[Get-TerminalCellSize] no CSI 16 t reply within ${TimeoutMilliseconds}ms - terminal does not report cell size"
		return $null
	}
	catch {
		Write-LogDebug "[Get-TerminalCellSize] cell size query failed => $($_.Exception.Message)" -Style Warning
		return $null
	}
}

function Test-TerminalCellSizeReply {
	<#
	.SYNOPSIS
		Tells whether a string holds a complete XTWINOPS cell-size report.

	.DESCRIPTION
		Private helper of Get-TerminalCellSize. Matches the full `CSI 6 ; height ; width t` shape -
		escape, bracket, the `6` selector and both numbers - anywhere in the text, so characters
		queued before or after the report do not matter and a bare `t` never counts as one. Used
		to decide when the console read can stop, and to tell "no reply" apart from "a reply with
		a degenerate size".

	.PARAMETER Text
		Everything read from the console input buffer so far.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[AllowEmptyString()]
		[string]$Text
	)

	return $Text -match "$([char]27)\[6;\d+;\d+t"
}

function ConvertFrom-TerminalCellSizeReply {
	<#
	.SYNOPSIS
		Parses the cell size out of an XTWINOPS report, or returns $null.

	.DESCRIPTION
		Private helper of Get-TerminalCellSize. Extracts the `CSI 6 ; height ; width t` report from
		the text - height first, which is easy to transpose - and returns it as an object with
		Width and Height in pixels. Returns $null when the text holds no complete report, or when
		the report describes a degenerate cell (a zero in either dimension), because a terminal
		that reports a degenerate cell is as useless as one that reports nothing.

	.PARAMETER Text
		Everything read from the console input buffer, in the order it arrived.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param(
		[AllowEmptyString()]
		[string]$Text
	)

	if ($Text -notmatch "$([char]27)\[6;(\d+);(\d+)t") { return $null }

	$size = [pscustomobject]@{
		Width  = [int]$Matches[2]
		Height = [int]$Matches[1]
	}

	if ($size.Width -lt 1 -or $size.Height -lt 1) { return $null }

	return $size
}

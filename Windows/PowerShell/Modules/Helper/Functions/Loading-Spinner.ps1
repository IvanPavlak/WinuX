function Loading-Spinner {
	<#
    .SYNOPSIS
        Display an animated loading spinner or run code with spinner feedback.

    .DESCRIPTION
        Four modes: Run scriptblock with spinner, Start continuous spinner, Stop
        spinner, and Pause/Resume an active spinner.

        The continuous (-Start) spinner is globally coordinated: there is only ever a
        SINGLE animation timer and a SINGLE spinner line on screen, no matter how many
        nested -Start calls are made. A nested -Start (e.g. Start-FancyZones started
        while a workspace layout spinner is already running) does NOT spawn a second
        timer; it simply relabels the existing spinner. The matching -Stop reverts the
        label to the parent's, and only the outermost -Stop tears the timer down. This
        prevents two background threads from fighting over the cursor.

        Rendering is done purely with carriage returns (no absolute cursor positioning),
        so the spinner is immune to terminal scrolling and works even when output is
        redirected.

        When surrounding code needs to print its own output WHILE the spinner is live,
        wrap that output in -Pause / -Resume so the spinner line is erased first and
        re-drawn afterwards, keeping all output in order and free of overlap.

    .PARAMETER Function
        Scriptblock to execute while showing spinner (Function parameter set).

    .PARAMETER Label
        Text label to display with spinner (optional).

    .PARAMETER Style
        Spinner animation style (default: 'Dots'). Must exist in Configuration.LoadingSpinners.

    .PARAMETER Start
        Start a new spinner (returns a handle hashtable for later Stop).

    .PARAMETER Stop
        Stop an active spinner (pass the handle from Start).

    .PARAMETER Spinner
        The spinner handle hashtable to stop (used with -Stop).

    .PARAMETER Completed
        Used with -Stop. Forces a green checkmark to be left on the line even when the
        spinner had no label (an empty-label spinner normally just erases on stop).
        Ignored when the spinner has a label (it always leaves "✓ label") or with -Discard.

    .PARAMETER Discard
        Used with -Stop. Erases the spinner line without leaving any checkmark, regardless
        of the label. Use this on error/abort paths so a success "✓" is never shown before
        a failure message. Takes precedence over -Completed and the label checkmark.

    .PARAMETER Pause
        Temporarily erase the active spinner line so other output can be written cleanly,
        reclaiming the spinner's own line so it leaves no blank residue. The next section's
        leading newline then reuses the spinner's reserve blank as its separator.

    .PARAMETER Resume
        Re-draw the spinner after a -Pause, one blank line below the output printed while
        paused (mirroring the reserve blank a fresh -Start emits).

    .EXAMPLE
        Loading-Spinner -Function { Start-Sleep 3 } -Label "Processing"

        $spinner = Loading-Spinner -Start -Label "Downloading" -Style "Bar"
        Start-Sleep 5
        Loading-Spinner -Stop -Spinner $spinner

        $spinner = Loading-Spinner -Start -Label "Working"
        Loading-Spinner -Pause
        Write-Host "`nSome status the caller wants to print"
        Loading-Spinner -Resume
        Loading-Spinner -Stop -Spinner $spinner
    #>
	[CmdletBinding(DefaultParameterSetName = 'Function')]
	param(
		[Parameter(ParameterSetName = 'Function', Mandatory = $true)]
		[scriptblock]$Function,

		[Parameter(ParameterSetName = 'Function', Mandatory = $false)]
		[Parameter(ParameterSetName = 'Start', Mandatory = $false)]
		[string]$Label = "",

		[Parameter(ParameterSetName = 'Function', Mandatory = $false)]
		[Parameter(ParameterSetName = 'Start', Mandatory = $false)]
		[string]$Style = "Dots",

		[Parameter(ParameterSetName = 'Start', Mandatory = $true)]
		[switch]$Start,

		[Parameter(ParameterSetName = 'Stop', Mandatory = $true)]
		[switch]$Stop,

		[Parameter(ParameterSetName = 'Stop', Mandatory = $false)]
		[hashtable]$Spinner,

		[Parameter(ParameterSetName = 'Stop', Mandatory = $false)]
		[switch]$Completed,

		[Parameter(ParameterSetName = 'Stop', Mandatory = $false)]
		[switch]$Discard,

		[Parameter(ParameterSetName = 'Pause', Mandatory = $true)]
		[switch]$Pause,

		[Parameter(ParameterSetName = 'Resume', Mandatory = $true)]
		[switch]$Resume
	)

	# Draw the current top-of-stack frame on the current line, clearing any
	# leftover characters from a previous (longer) label, then park the cursor
	# back at column 0 so the next write overwrites in place. Assumes the caller
	# already holds the coordinator lock. No absolute cursor positioning is used,
	# so scrolling can never desync the spinner.
	$renderFrame = {
		param($c)
		if ($c.Stack.Count -eq 0) { return }
		$entry = $c.Stack[$c.Stack.Count - 1]
		$symbol = $c.Symbols[$c.Index]
		$text = if ([string]::IsNullOrEmpty($entry.Label)) { [string]$symbol } else { "$symbol $($entry.Label)" }
		$pad = if ($c.LastLen -gt $text.Length) { ' ' * ($c.LastLen - $text.Length) } else { '' }
		Write-Host -NoNewline ("`r" + $text + $pad + "`r") -ForegroundColor DarkCyan
		$c.LastLen = $text.Length
		$c.Index = ($c.Index + 1) % $c.Symbols.Count
	}

	# Blank the spinner line in place. Assumes the caller holds the coordinator lock.
	$eraseLine = {
		param($c)
		if ($c.LastLen -gt 0) {
			Write-Host -NoNewline ("`r" + (' ' * $c.LastLen) + "`r")
			$c.LastLen = 0
		}
	}

	# ============================ STOP ============================
	if ($PSCmdlet.ParameterSetName -eq 'Stop') {
		$c = $global:LoadingSpinnerCoordinator
		if (-not $c -or -not $Spinner) { return }
		$id = $Spinner.Id

		$finalizeLabel = $null
		$shouldFinalize = $false
		$timerToStop = $null
		$subToRemove = $null

		[System.Threading.Monitor]::Enter($c.Lock)
		try {
			# Remove this spinner from the stack (idempotent if already gone).
			for ($i = $c.Stack.Count - 1; $i -ge 0; $i--) {
				if ($c.Stack[$i].Id -eq $id) {
					if ($i -eq $c.Stack.Count - 1) { $finalizeLabel = $c.Stack[$i].Label }
					$c.Stack.RemoveAt($i)
					break
				}
			}

			if ($c.Stack.Count -gt 0) {
				# A parent spinner is still active: just revert the label. Keep
				# LastLen as-is so renderFrame clears any longer previous label.
				if (-not $c.Suspended) { & $renderFrame $c }
				return
			}

			# Stack is empty: tear the whole spinner down.
			$shouldFinalize = $true
			$c.Active = $false
			$timerToStop = $c.Timer
			$subToRemove = $c.EventSub
			$c.Timer = $null
			$c.EventSub = $null
		}
		finally {
			[System.Threading.Monitor]::Exit($c.Lock)
		}

		if (-not $shouldFinalize) { return }

		# Stop/dispose the timer and unregister the event OUTSIDE the lock. The
		# Elapsed handler also takes the lock, so disposing while holding it could
		# deadlock. Active is already $false, so any in-flight tick is a no-op.
		if ($timerToStop) {
			try { $timerToStop.Stop() } catch {}
			try { $timerToStop.Dispose() } catch {}
		}
		if ($subToRemove) {
			Unregister-Event -SubscriptionId $subToRemove.Id -ErrorAction SilentlyContinue
			Remove-Job -Id $subToRemove.Id -Force -ErrorAction SilentlyContinue
		}

		# Write the final state. The timer is gone, but keep the lock to stay
		# consistent with Pause/Resume on other threads.
		[System.Threading.Monitor]::Enter($c.Lock)
		try {
			if ($Discard) {
				# Caller is aborting (error/cancel): erase the line, never a checkmark.
				if (-not $c.Suspended) { & $eraseLine $c }
			}
			elseif (-not [string]::IsNullOrEmpty($finalizeLabel)) {
				# Replace the spinner line with a green "✓ label".
				$doneText = " ✓ $finalizeLabel"
				if ($c.Suspended) {
					Write-Host $doneText -ForegroundColor Green
				}
				else {
					$pad = if ($c.LastLen -gt $doneText.Length) { ' ' * ($c.LastLen - $doneText.Length) } else { '' }
					Write-Host ("`r" + $doneText + $pad) -ForegroundColor Green
				}
			}
			elseif ($Completed) {
				# Empty label but success signalled: leave a bare green checkmark.
				if ($c.Suspended) {
					Write-Host " ✓" -ForegroundColor Green
				}
				else {
					$doneText = " ✓"
					$pad = if ($c.LastLen -gt $doneText.Length) { ' ' * ($c.LastLen - $doneText.Length) } else { '' }
					Write-Host ("`r" + $doneText + $pad) -ForegroundColor Green
				}
			}
			else {
				# Purely decorative / no completion signal: just erase the line.
				if (-not $c.Suspended) { & $eraseLine $c }
			}

			# Reset for reuse on the next -Start.
			$c.Index = 0
			$c.LastLen = 0
			$c.Suspended = $false
			$c.Stack.Clear()
		}
		finally {
			[System.Threading.Monitor]::Exit($c.Lock)
		}
		return
	}

	# ============================ PAUSE ============================
	if ($PSCmdlet.ParameterSetName -eq 'Pause') {
		$c = $global:LoadingSpinnerCoordinator
		if (-not $c -or -not $c.Active) { return }
		[System.Threading.Monitor]::Enter($c.Lock)
		try {
			if (-not $c.Suspended) {
				$hadLine = $c.LastLen -gt 0
				& $eraseLine $c
				# The spinner always animates on its own line, one blank line below the
				# preceding output (the reserve blank emitted at -Start). Erasing only blanks
				# the spinner text in place - the now-empty line lingers, so the next section's
				# leading "`n" would stack a SECOND blank line on top of the reserve blank.
				# Move the cursor up one line to reclaim the spinner's own line; the next
				# section's leading newline then reuses the reserve blank as its separator,
				# keeping exactly one blank line between sections. -Resume re-emits the blank.
				if ($hadLine) {
					Write-Host -NoNewline ([char]27 + '[1A')
				}
				$c.Suspended = $true
			}
		}
		finally {
			[System.Threading.Monitor]::Exit($c.Lock)
		}
		return
	}

	# ============================ RESUME ============================
	if ($PSCmdlet.ParameterSetName -eq 'Resume') {
		$c = $global:LoadingSpinnerCoordinator
		if (-not $c -or -not $c.Active) { return }
		[System.Threading.Monitor]::Enter($c.Lock)
		try {
			if ($c.Suspended) {
				$c.Suspended = $false
				$c.LastLen = 0
				# Re-draw on a fresh line one blank line below whatever printed while paused,
				# mirroring the reserve blank a fresh -Start emits. This keeps a single blank
				# line between the paused section's output and the resumed spinner (and its
				# eventual "✓"), instead of the spinner butting directly against that output.
				Write-Host ""
				& $renderFrame $c
			}
		}
		finally {
			[System.Threading.Monitor]::Exit($c.Lock)
		}
		return
	}

	# ---- Spinner configuration is needed for Function and Start modes ----
	$spinners = $global:Configuration.LoadingSpinners
	if (-not $spinners) {
		Write-Host -ForegroundColor Red "`n=> Loading spinner configuration not found in global configuration"
		return
	}

	$selectedStyle = if ($Style) {
		$Style
	}
 elseif ($global:Configuration.DefaultSpinner) { $global:Configuration.DefaultSpinner }

	$spinnerConfig = $spinners[$selectedStyle]

	if (-not $spinnerConfig) {
		$availableSpinners = ($spinners.Keys | Sort-Object) -join ", "
		Write-Host -ForegroundColor Red "`n=> Spinner configuration for style [$selectedStyle] not found!"
		Write-Host -ForegroundColor DarkCyan "`n Available spinners => [$availableSpinners]"
		return
	}

	# ============================ START ============================
	if ($PSCmdlet.ParameterSetName -eq 'Start') {
		if (-not $global:LoadingSpinnerCoordinator) {
			$global:LoadingSpinnerCoordinator = @{
				Lock      = [System.Object]::new()
				Stack     = [System.Collections.Generic.List[object]]::new()
				Timer     = $null
				EventSub  = $null
				Symbols   = $spinnerConfig.Symbols
				Delay     = $spinnerConfig.Delay
				Index     = 0
				LastLen   = 0
				Active    = $false
				Suspended = $false
			}
		}

		$c = $global:LoadingSpinnerCoordinator
		$id = [Guid]::NewGuid().ToString()

		[System.Threading.Monitor]::Enter($c.Lock)
		try {
			$isFirst = (-not $c.Active)

			if ($isFirst) {
				# Adopt this start's style and reset render state.
				$c.Symbols = $spinnerConfig.Symbols
				$c.Delay = $spinnerConfig.Delay
				$c.Index = 0
				$c.LastLen = 0
				$c.Suspended = $false

				# Always start the spinner on its own fresh line - one blank line
				# before it animates. Neater, and consistent across all callers.
				Write-Host ""
			}

			$c.Stack.Add(@{ Id = $id; Label = $Label })

			if ($isFirst) {
				$c.Active = $true
				if (-not $c.Suspended) { & $renderFrame $c }

				$timer = New-Object System.Timers.Timer
				$timer.Interval = $c.Delay
				$timer.AutoReset = $true

				# The Elapsed handler runs on a thread-pool thread. It renders the
				# current frame under the shared lock and uses ONLY carriage returns
				# (no [Console] APIs) so it cannot throw on a redirected stream.
				$eventAction = {
					$cc = $Event.MessageData
					[System.Threading.Monitor]::Enter($cc.Lock)
					try {
						if (-not $cc.Active -or $cc.Suspended -or $cc.Stack.Count -eq 0) { return }
						$entry = $cc.Stack[$cc.Stack.Count - 1]
						$symbol = $cc.Symbols[$cc.Index]
						$text = if ([string]::IsNullOrEmpty($entry.Label)) { [string]$symbol } else { "$symbol $($entry.Label)" }
						$pad = if ($cc.LastLen -gt $text.Length) { ' ' * ($cc.LastLen - $text.Length) } else { '' }
						Write-Host -NoNewline ("`r" + $text + $pad + "`r") -ForegroundColor DarkCyan
						$cc.LastLen = $text.Length
						$cc.Index = ($cc.Index + 1) % $cc.Symbols.Count
					}
					catch {}
					finally {
						[System.Threading.Monitor]::Exit($cc.Lock)
					}
				}

				$sub = Register-ObjectEvent -InputObject $timer `
					-EventName Elapsed `
					-Action $eventAction `
					-MessageData $c

				$c.Timer = $timer
				$c.EventSub = $sub
				$timer.Start()
			}
			else {
				# Nested start: reuse the single timer, just show the new label.
				# Keep LastLen so renderFrame clears any longer previous label.
				if (-not $c.Suspended) { & $renderFrame $c }
			}
		}
		finally {
			[System.Threading.Monitor]::Exit($c.Lock)
		}

		return @{ Id = $id; Label = $Label }
	}

	# ======================= FUNCTION (job-based) =======================
	# Single-threaded: the work runs in a background job while the main thread
	# animates, so there is no cross-thread console contention here.
	$job = Start-Job -ScriptBlock $Function

	$symbols = $spinnerConfig.Symbols
	$delay = $spinnerConfig.Delay
	$i = 0
	$lastLen = 0

	Write-Host ""

	while ($job.State -eq "Running") {
		$symbol = $symbols[$i]
		$text = if ([string]::IsNullOrEmpty($Label)) { [string]$symbol } else { "$symbol $Label" }
		$pad = if ($lastLen -gt $text.Length) { ' ' * ($lastLen - $text.Length) } else { '' }
		Write-Host -NoNewLine ("`r" + $text + $pad) -ForegroundColor DarkCyan
		$lastLen = $text.Length
		Start-Sleep -Milliseconds $delay
		$i = ($i + 1) % $symbols.Count
	}

	# Show green checkmark when done, clearing any leftover spinner characters.
	$doneText = if ([string]::IsNullOrEmpty($Label)) { " ✓" } else { " ✓ $Label" }
	$pad = if ($lastLen -gt $doneText.Length) { ' ' * ($lastLen - $doneText.Length) } else { '' }
	Write-Host ("`r" + $doneText + $pad) -ForegroundColor Green

	return Receive-Job -Job $job
}

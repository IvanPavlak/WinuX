function Write-Log {
	<#
	.SYNOPSIS
		Core logging engine: renders a styled, leveled message to the console and mirrors it to the structured log files.

	.DESCRIPTION
		The single source of truth for repository console output. Every Write-Log* wrapper
		(Write-LogTitle, Write-LogStep, Write-LogSuccess, Write-LogWarning, Write-LogError,
		Write-LogDebug) calls this engine. Prefer the wrappers in normal code; call Write-Log
		directly only when the level must be selected dynamically.

		Console rendering reproduces the repository's house style exactly:
		  Title    => DarkCyan  "`n[Message]"
		  Step     => White     "`nMessage"
		  Success  => Green      "`n=> Message"
		  Warning  => Yellow     "`n=> Message"
		  Error    => Red        "`n=> Message"
		  Debug    => DarkCyan    "`n [Caller] Message"   (verbose-gated)

		Colors come from $Configuration.Logging.Colors (falling back to the documented defaults),
		so the palette is data-driven but unchanged out of the box.

		Verbosity: Debug-level lines print to the console only when verbose logging is active - that
		is when Set-LogLevel set the session (or a scoped command) to Verbose, or when a global
		$VerbosePreference = 'Continue' is in effect. Set-LogLevel is the cross-module-reliable
		verbosity control. Suppressed Debug lines are still written to the file log at full detail.

		File logging: when enabled, every call (including suppressed Debug lines) is appended to the
		current session log as "[timestamp] [LEVEL] [Caller] message". Errors are additionally
		appended verbosely (message + exception + stack trace) to the shared error log.

	.PARAMETER Message
		The message text. Do NOT embed the leading "`n", the "=>" prefix, or the "[ ]" title
		brackets - the engine adds the level-appropriate decoration. Leading-space indentation in
		the message is preserved.

	.PARAMETER Level
		Title | Step | Success | Warning | Error | Debug. Defaults to Step.

	.PARAMETER Style
		Only meaningful when Level=Debug or Level=Step: render the message in another level's color
		while keeping the level's own layout, gating, and file-log tag (e.g. -Style Success keeps a
		green diagnostic, or colors a Step row by outcome). Defaults to the level's own color.

	.PARAMETER NoNewLine
		Suppress the trailing newline (maps to Write-Host -NoNewline) for composing a line across
		multiple calls.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n" the engine normally prepends.

	.PARAMETER BlankLineAfter
		Emit one extra trailing newline so a blank line follows the message (console only; the file log is
		unaffected). Use it to reproduce a section header's original "blank line after" spacing, e.g.
		Write-LogTitle "Reloading Custom Modules" -BlankLineAfter. Ignored when -NoNewLine is set.

	.PARAMETER Exception
		An ErrorRecord or Exception whose details and stack trace are written verbosely to the
		error log. Honored only for Level=Error.

	.EXAMPLE
		Write-Log -Level Success -Message "Workspace opened!"

	.EXAMPLE
		Write-Log -Level Debug -Message "Captured $n handle(s)" -Style Step
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[ValidateSet("Title", "Step", "Success", "Warning", "Error", "Debug")]
		[string]$Level = "Step",

		[Parameter(Mandatory = $false)]
		[ValidateSet("Title", "Step", "Success", "Warning", "Error", "Debug")]
		[string]$Style,

		[Parameter(Mandatory = $false)]
		[switch]$NoNewLine,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[object]$Exception,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)

	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	$state = $global:LoggingState

	# --- Resolve palette (config-driven, documented defaults) ---
	# Debug and Step accept a -Style color override (layout/gating stay the level's own)
	$renderStyle = if (($Level -eq "Debug" -or $Level -eq "Step") -and $Style) { $Style } else { $Level }
	$color = $state.Colors[$renderStyle]
	if (-not $color) { $color = "White" }

	# --- Determine console visibility ---
	# Set-LogLevel (global state) is the cross-module control; a global $VerbosePreference is also honored.
	$verboseActive = ($state.Level -eq "Verbose") -or ($VerbosePreference -ne "SilentlyContinue")
	$showOnConsole = $true
	if ($state.Level -eq "Quiet") { $showOnConsole = ($Level -eq "Error" -or $Level -eq "Warning") }
	if ($Level -eq "Debug") { $showOnConsole = $showOnConsole -and $verboseActive }

	# --- Resolve the originating caller (skip the Write-Log* frames) ---
	$caller = "Console"
	try {
		$stack = Get-PSCallStack
		for ($i = 1; $i -lt $stack.Count; $i++) {
			$cmd = $stack[$i].Command
			if ($cmd -and $cmd -notlike "Write-Log*") { $caller = $cmd; break }
		}
	}
	catch { }

	# --- Build console text matching the house style exactly ---
	$lead = if ($NoLeadingNewline) { "" } else { "`n" }
	switch ($Level) {
		"Title" { $text = "$lead[$Message]" }
		"Success" { $text = "$lead=> $Message" }
		"Warning" { $text = "$lead $Message" }
		"Error" { $text = "$lead=> $Message" }
		"Debug" { $text = "$lead [$caller] $Message" }
		default { $text = "$lead$Message" }
	}

	if ($showOnConsole) {
		# -BlankLineAfter appends an extra newline so a blank line follows (reproduces an original
		# trailing-"`n" spacer). Meaningless with -NoNewLine, so it is ignored there.
		$consoleText = if ($BlankLineAfter -and -not $NoNewLine) { "$text`n" } else { $text }
		if ($NoNewLine) {
			Write-Host -ForegroundColor $color -NoNewline -Object $consoleText
		}
		else {
			Write-Host -ForegroundColor $color -Object $consoleText
		}
	}

	# --- Mirror to the structured file log (always, full detail) ---
	if ($state.FileLogging -and $state.SessionFile) {
		try {
			$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
			$fileLine = "[$stamp] [$($Level.ToUpper())] [$caller] $Message"
			Add-Content -Path $state.SessionFile -Value $fileLine -Encoding UTF8 -ErrorAction Stop

			if ($Level -eq "Error") {
				$errorLines = @($fileLine)
				if ($Exception) {
					if ($Exception -is [System.Management.Automation.ErrorRecord]) {
						$errorLines += "    Exception => $($Exception.Exception.Message)"
						if ($Exception.ScriptStackTrace) {
							foreach ($traceLine in ($Exception.ScriptStackTrace -split "`r?`n")) {
								$errorLines += "      $traceLine"
							}
						}
					}
					else {
						$errorLines += "    Exception => $($Exception.Message)"
						if ($Exception.StackTrace) {
							foreach ($traceLine in ($Exception.StackTrace -split "`r?`n")) {
								$errorLines += "      $traceLine"
							}
						}
					}
				}
				Add-Content -Path $state.ErrorFile -Value $errorLines -Encoding UTF8 -ErrorAction Stop
			}
		}
		catch { }
	}
}

function Invoke-Onefetch {
	<#
	.SYNOPSIS
		Displays the onefetch repository info panel when the shell is inside a git repository -
		the third step of Show-TerminalGreeting.

	.DESCRIPTION
		Runs `onefetch` in the current directory, and does nothing at all - silently, with one
		debug line saying why - in any of the four cases where it would be noise:

		  - TerminalGreeting.Onefetch.Enabled is $false. This is the shipped default: onefetch is
		    opt-in, because it is only meaningful inside a repository and not every machine has the
		    binary.
		  - The onefetch binary is not installed.
		  - The current directory is not inside a repository (Test-GitRepository walks up looking
		    for a .git entry, without spawning a process).
		  - onefetch itself exits non-zero, which is what an empty repository with no commits looks
		    like. Its stderr is suppressed; the exit code is logged at debug level only.

		Silence is the point. This runs on every `c` and every shell start, including in directories
		that have nothing to do with git, and a greeting is the wrong place to learn that a binary is
		missing.

		-Measure captures the output instead of displaying it and returns the number of rows it
		would occupy, so Show-TerminalGreeting can add that height to the fit budget it hands
		Invoke-Fastfetch - the font is then chosen for both panels together. It returns 0 in every
		case where the display run would print nothing. Like fastfetch, onefetch emits one line per
		visual row when its output is redirected, so the captured line count is the height.

	.PARAMETER Measure
		Return the row count of the panel instead of displaying it. 0 when nothing would be shown.

	.PARAMETER Arguments
		Arguments passed through to the onefetch binary. Defaults to
		TerminalGreeting.Onefetch.Arguments.

	.PARAMETER Path
		The directory to test and run in. Defaults to the current location.

	.PARAMETER Settings
		The resolved greeting settings from Resolve-TerminalGreetingSettings. Show-TerminalGreeting
		resolves once and passes the tree down; omitted, this function resolves for itself, so it is
		usable on its own.

	.OUTPUTS
		Nothing, or - with -Measure - an [int] row count.

	.EXAMPLE
		Invoke-Onefetch
		Shows the repository panel, if onefetch is enabled, installed, and this is a repository.

	.EXAMPLE
		Invoke-Onefetch -Measure
		Returns how many rows the panel would take, without printing anything.

	.EXAMPLE
		Invoke-Onefetch -Arguments "--no-art"
		Shows the panel without the ASCII language logo, whatever the configuration says.

	.EXAMPLE
		Set-LogLevel Verbose { Invoke-Onefetch }
		Prints the reason when nothing is shown.
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[switch]$Measure,

		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$Arguments,

		[AllowNull()]
		[AllowEmptyString()]
		[string]$Path = $PWD.Path,

		[AllowNull()]
		[psobject]$Settings
	)

	if (-not $Settings) { $Settings = Resolve-TerminalGreetingSettings }

	# The three reasons to do nothing, checked cheapest first: a flag, then a command lookup, then
	# a walk up the directory tree.
	$reason = if (-not $Settings.Onefetch.Enabled) { "TerminalGreeting.Onefetch.Enabled is false" }
	elseif (-not (Get-Command -Name onefetch -ErrorAction SilentlyContinue)) { "onefetch is not installed" }
	elseif (-not (Test-GitRepository -Path $Path)) { "[$Path] is not inside a git repository" }

	if ($reason) {
		Write-LogDebug "[Invoke-Onefetch] skipped => $reason"
		# 0 rows, so a skipped panel leaves the caller's fit budget untouched.
		if ($Measure) { return 0 }
		return
	}

	if (-not $PSBoundParameters.ContainsKey("Arguments")) { $Arguments = $Settings.Onefetch.Arguments }
	$onefetchArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })

	if ($Measure) {
		# Redirected output puts onefetch in plain mode: one line per visual row, no color or
		# cursor escape sequences, so the captured line count is the panel height.
		$captured = @(onefetch @onefetchArgs 2>$null)
		if ($LASTEXITCODE -ne 0) {
			Write-LogDebug "[Invoke-Onefetch] measured 0 rows => onefetch exited $LASTEXITCODE (an empty repository has nothing to report)"
			return 0
		}
		Write-LogDebug "[Invoke-Onefetch] measured $($captured.Count) row(s)"
		return $captured.Count
	}

	onefetch @onefetchArgs 2>$null
	if ($LASTEXITCODE -ne 0) {
		Write-LogDebug "[Invoke-Onefetch] onefetch exited $LASTEXITCODE (an empty repository has nothing to report)"
	}
}

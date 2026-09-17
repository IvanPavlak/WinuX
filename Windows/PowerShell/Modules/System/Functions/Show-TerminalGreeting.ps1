function Show-TerminalGreeting {
	<#
	.SYNOPSIS
		Clears the terminal and shows the system info panel, plus the repository panel when the
		shell is inside a git repository. Alias: c

	.DESCRIPTION
		The greeting a shell opens with, and what the `c` alias redraws. Three steps, each its own
		exported function and each independently switchable from configuration or from a switch on
		this call:

		  Invoke-Clear     Clear-Host.                                   On by default.
		  Invoke-Fastfetch The fastfetch system info panel, font-fitted. On by default.
		  Invoke-Onefetch  The onefetch repository panel.                OFF by default.

		Onefetch is opt-in because it is only meaningful inside a repository and not every machine
		has the binary; enabled, it is still silently skipped outside a repository, so there is no
		directory where the greeting prints an error or an empty panel.

		The order is deliberate. Onefetch is MEASURED first, before anything is drawn, so its height
		can be added to the budget Invoke-Fastfetch fits the font to - the font is then chosen for
		both panels together rather than for fastfetch alone, which would fit and then scroll off
		the top as soon as onefetch printed below it. Set
		TerminalGreeting.Onefetch.IncludeInAutoFit to $false to fit fastfetch on its own. The screen
		is cleared before the shrink keystrokes rather than after, so the Ctrl+0 / Ctrl+Minus steps
		happen on an empty screen; the alternative - clearing last - would mean drawing the panel
		onto whatever was already there.

		Settings are resolved exactly once, by Resolve-TerminalGreetingSettings, and handed to each
		step, so a value out of range is reported once per greeting rather than three times. A
		configuration with no TerminalGreeting section falls through to the built-in defaults, which
		are the values the base ships - so a fork that has not migrated its Configuration.local.psd1
		gets the previous behavior: clear, then a font-fitted fastfetch.

		The -No* switches turn one step off for one call. The four auto-fit knobs forward to
		Invoke-Fastfetch, where an explicit value beats the configured one for that call.

	.PARAMETER NoClear
		Skip the clear step for this call.

	.PARAMETER NoFastfetch
		Skip the fastfetch step for this call.

	.PARAMETER NoOnefetch
		Skip the onefetch step for this call - including its measurement, so the font is fitted to
		fastfetch alone.

	.PARAMETER NoResize
		Skip the font auto-fit. The profile passes this at startup: a fresh shell has nothing on
		screen to redraw and the keystroke round trips would only delay the first prompt.

	.PARAMETER PromptReserve
		Rows kept free below the panel for the upcoming prompt. Overrides
		TerminalGreeting.Fastfetch.AutoFit.PromptReserve for this call.

	.PARAMETER MaxShrinkSteps
		Upper bound on the Ctrl+Minus steps taken below the default font. Overrides
		TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps for this call. 0 resets the font to the
		default and never shrinks.

	.PARAMETER ReflowTimeoutMilliseconds
		How long to wait for the window size to change after each keystroke. Overrides
		TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds for this call.

	.EXAMPLE
		c
		The whole greeting, as configured.

	.EXAMPLE
		Show-TerminalGreeting -NoOnefetch
		Clears and shows the system info panel only, fitted to itself.

	.EXAMPLE
		Show-TerminalGreeting -NoResize
		The greeting without the font auto-fit - what the profile runs at shell start.

	.EXAMPLE
		Show-TerminalGreeting -MaxShrinkSteps 0
		Resets the font to the default and shrinks nothing, to see whether the panels fit at all at
		the default size.

	.EXAMPLE
		Set-LogLevel Verbose { Show-TerminalGreeting }
		Prints what was measured, how many steps were taken, and why any step was skipped.
	#>
	[CmdletBinding()]
	param(
		[switch]$NoClear,

		[switch]$NoFastfetch,

		[switch]$NoOnefetch,

		[switch]$NoResize,

		[AllowNull()]
		[nullable[int]]$PromptReserve,

		[AllowNull()]
		[nullable[int]]$MaxShrinkSteps,

		[AllowNull()]
		[nullable[int]]$ReflowTimeoutMilliseconds
	)

	# Resolved once for the whole greeting: configuration beats defaults, an explicit parameter
	# beats both - but only the parameters actually passed, so an unbound one leaves the configured
	# value alone.
	$overrides = @{}
	foreach ($name in "PromptReserve", "MaxShrinkSteps", "ReflowTimeoutMilliseconds") {
		if ($PSBoundParameters.ContainsKey($name)) { $overrides[$name] = $PSBoundParameters[$name] }
	}
	$settings = Resolve-TerminalGreetingSettings @overrides

	$showOnefetch = -not $NoOnefetch

	# Measure onefetch before anything is drawn, so its rows are part of the budget the font is
	# fitted to. Invoke-Onefetch returns 0 whenever it would print nothing, so a disabled step, a
	# missing binary and a non-repository directory all cost the fit nothing.
	$extraRows = 0
	if ($showOnefetch -and $settings.Onefetch.IncludeInAutoFit -and -not $NoFastfetch -and -not $NoResize) {
		$extraRows = Invoke-Onefetch -Measure -Settings $settings
	}

	if (-not $NoClear) { Invoke-Clear -Settings $settings }

	if (-not $NoFastfetch) {
		Invoke-Fastfetch -Settings $settings -ExtraRows $extraRows -NoResize:$NoResize
	}

	if ($showOnefetch) { Invoke-Onefetch -Settings $settings }
}

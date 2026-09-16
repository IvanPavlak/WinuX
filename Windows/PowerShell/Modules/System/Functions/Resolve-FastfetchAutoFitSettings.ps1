function Resolve-FastfetchAutoFitSettings {
	<#
	.SYNOPSIS
		Resolves the font auto-fit settings Invoke-ClearAndFastfetch runs with.

	.DESCRIPTION
		Merges three layers into one settled object, per key: an explicit parameter beats the
		FastfetchAutoFit configuration section, which beats the built-in default. The keys are

		  MaxShrinkSteps             Ctrl+Minus steps allowed below the default font. 0-50. Default 10.
		  ReflowTimeoutMilliseconds  How long to wait for the window to change after a keystroke.
		                             Any positive integer - this is the knob to tweak per terminal and
		                             machine, so no upper bound is imposed. Default 10.
		  PromptReserve              Rows kept free below the panel for the prompt. 0-20. Default 1.

		A value that is not an integer in range - from either layer - is reported through
		Write-LogWarning and the built-in default is used for that key, so a typo in
		Configuration.local.psd1 degrades the auto-fit to its defaults rather than throwing at
		the prompt. $null (or a missing key) in configuration means "use the default" silently,
		which is also what the base configuration ships for a key a fork does not change.

		Invoke-ClearAndFastfetch calls this exactly once per invocation. It has no side effect
		beyond the warnings, so it is safe to call ad hoc to see what `c` would run with under
		the current configuration.

	.PARAMETER Settings
		The FastfetchAutoFit configuration section. Defaults to
		$global:Configuration.FastfetchAutoFit. $null or empty means every key falls through
		to the built-in default (or to the explicit parameter).

	.PARAMETER MaxShrinkSteps
		Explicit override for MaxShrinkSteps.

	.PARAMETER ReflowTimeoutMilliseconds
		Explicit override for ReflowTimeoutMilliseconds.

	.PARAMETER PromptReserve
		Explicit override for PromptReserve.

	.OUTPUTS
		[pscustomobject] with MaxShrinkSteps, ReflowTimeoutMilliseconds and PromptReserve, all [int].

	.EXAMPLE
		Resolve-FastfetchAutoFitSettings
		Returns the settings a parameterless `c` would use with the current configuration.

	.EXAMPLE
		Resolve-FastfetchAutoFitSettings -MaxShrinkSteps 0
		Returns the settings with shrinking disabled, whatever the configuration says.

	.EXAMPLE
		Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = "many" }
		Warns that MaxShrinkSteps must be an integer between 0 and 50 and returns the default 10 for it.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[hashtable]$Settings = $global:Configuration.FastfetchAutoFit,

		[AllowNull()]
		[nullable[int]]$MaxShrinkSteps,

		[AllowNull()]
		[nullable[int]]$ReflowTimeoutMilliseconds,

		[AllowNull()]
		[nullable[int]]$PromptReserve
	)

	# Built-in defaults and the range each key must fall in. The base configuration ships
	# exactly these values, so a vanilla install and a missing section behave identically.
	# A $null Maximum means no upper bound: the reflow timeout is the per-machine tuning knob
	# and a user testing a slow terminal must be free to go as high as it takes.
	$rules = [ordered]@{
		MaxShrinkSteps            = @{ Default = 10; Minimum = 0; Maximum = 50; Shape = "an integer between 0 and 50" }
		ReflowTimeoutMilliseconds = @{ Default = 10; Minimum = 1; Maximum = $null; Shape = "a positive integer" }
		PromptReserve             = @{ Default = 1; Minimum = 0; Maximum = 20; Shape = "an integer between 0 and 20" }
	}

	$overrides = @{
		MaxShrinkSteps            = $MaxShrinkSteps
		ReflowTimeoutMilliseconds = $ReflowTimeoutMilliseconds
		PromptReserve             = $PromptReserve
	}

	$resolved = [ordered]@{}

	foreach ($key in $rules.Keys) {
		$rule = $rules[$key]
		$value = $rule.Default
		$source = "default"

		# Configuration layer. $null / missing is the silent "use the default".
		if ($Settings -and $Settings.Contains($key) -and $null -ne $Settings[$key]) {
			$candidate = 0
			$parsed = [int]::TryParse("$($Settings[$key])", [ref]$candidate)
			if ($parsed -and $candidate -ge $rule.Minimum -and ($null -eq $rule.Maximum -or $candidate -le $rule.Maximum)) {
				$value = $candidate
				$source = "configuration"
			}
			else {
				Write-LogWarning "Configuration.FastfetchAutoFit.$key must be $($rule.Shape) - got [$($Settings[$key])]. Using the default [$($rule.Default)]."
			}
		}

		# Explicit parameter layer, validated the same way so a bad call-site value is reported
		# rather than silently accepted.
		if ($null -ne $overrides[$key]) {
			$candidate = [int]$overrides[$key]
			if ($candidate -ge $rule.Minimum -and ($null -eq $rule.Maximum -or $candidate -le $rule.Maximum)) {
				$value = $candidate
				$source = "parameter"
			}
			else {
				Write-LogWarning "-$key must be $($rule.Shape) - got [$candidate]. Using [$value] ($source)."
			}
		}

		Write-LogDebug "[Resolve-FastfetchAutoFitSettings] $key = $value ($source)"
		$resolved[$key] = $value
	}

	return [pscustomobject]$resolved
}

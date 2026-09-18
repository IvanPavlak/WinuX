function Resolve-TerminalGreetingSettings {
	<#
	.SYNOPSIS
		Resolves the settings Show-TerminalGreeting and its three steps run with.

	.DESCRIPTION
		Merges three layers into one settled tree, per key: an explicit parameter beats the
		TerminalGreeting configuration section, which beats the built-in default. The tree it
		returns is the whole greeting, not one step of it, so every caller reads the same object
		and the section is parsed exactly once per greeting.

		  Clear.Enabled                        Whether Invoke-Clear runs. Default $true.
		  Fastfetch.Enabled                    Whether Invoke-Fastfetch runs. Default $true.
		  Fastfetch.AutoFit.Enabled            Whether the font is fitted to the panel. Default $true.
		  Fastfetch.AutoFit.MaxShrinkSteps     Ctrl+Minus steps allowed below the default font. 0-50. Default 10.
		  Fastfetch.AutoFit.ReflowTimeoutMilliseconds
		                                       How long to wait for the window to change after a keystroke.
		                                       Any positive integer - this is the knob to tweak per terminal
		                                       and machine, so no upper bound is imposed. Default 10.
		  Fastfetch.AutoFit.PromptReserve      Rows kept free below the panel for the prompt. 0-20. Default 1.
		  Onefetch.Enabled                     Whether Invoke-Onefetch runs. Default $false - onefetch is
		                                       opt-in, because it is only meaningful inside a repository and
		                                       not every machine has the binary.
		  Onefetch.IncludeInAutoFit            Whether onefetch's height is added to the fit budget, so the
		                                       font is chosen for both panels together. Default $true.
		  Onefetch.InProjectTerminals          Whether Open-ProjectTerminals appends Invoke-Onefetch to each
		                                       project tab's command. Default $true. The greeting cannot
		                                       cover those tabs - a tab's profile runs BEFORE the
		                                       Set-Location that moves it into the repository - so the
		                                       append is the only way they get the panel.
		  Onefetch.Arguments                   Extra arguments passed to the onefetch binary. Default @().
		  Onefetch.Style.Enabled               Whether onefetch's output is restyled on its way to the
		                                       screen by Format-OnefetchPanel. Default $false - the
		                                       panel is onefetch's own until a fork asks otherwise.
		  Onefetch.Style.Separator             Replaces onefetch's hardcoded ":" after each field name,
		                                       for example " -> ". Default "" - keep the colon.
		  Onefetch.Style.Colors                Maps an ANSI index onefetch was told to use onto the SGR
		                                       parameters to paint it with instead, as
		                                       @{ "12" = "38;2;30;144;255" }. This is the only way to a
		                                       true color: --text-colors takes 0-15 and nothing else.
		                                       Default @{} - repaint nothing.

		A value that is not an integer in range - from either layer - is reported through
		Write-LogWarning and the built-in default is used for that key, so a typo in
		Configuration.local.psd1 degrades the greeting to its defaults rather than throwing at the
		prompt. $null (or a missing key) in configuration means "use the default" silently, which is
		also what the base configuration ships for a key a fork does not change. A missing
		TerminalGreeting section is therefore not an error: every key falls through and the greeting
		behaves exactly like the shipped defaults.

		Booleans are read with PowerShell's own truthiness rather than a parser, because a psd1 can
		only write $true / $false / a number / a string there and every one of those has an obvious
		reading. Arguments accepts a single string or an array and is normalized to [string[]],
		with blank entries dropped.

		Show-TerminalGreeting calls this exactly once per invocation and hands the result to each
		step, so a bad value is reported once rather than three times. It has no side effect beyond
		the warnings, so it is safe to call ad hoc to see what `c` would run with under the current
		configuration.

	.PARAMETER Settings
		The TerminalGreeting configuration section. Defaults to
		$global:Configuration.TerminalGreeting. $null or empty means every key falls through to the
		built-in default (or to the explicit parameter).

	.PARAMETER MaxShrinkSteps
		Explicit override for Fastfetch.AutoFit.MaxShrinkSteps.

	.PARAMETER ReflowTimeoutMilliseconds
		Explicit override for Fastfetch.AutoFit.ReflowTimeoutMilliseconds.

	.PARAMETER PromptReserve
		Explicit override for Fastfetch.AutoFit.PromptReserve.

	.OUTPUTS
		[pscustomobject] with Clear, Fastfetch (carrying AutoFit) and Onefetch branches.

	.EXAMPLE
		Resolve-TerminalGreetingSettings
		Returns the settings a parameterless `c` would use with the current configuration.

	.EXAMPLE
		Resolve-TerminalGreetingSettings -MaxShrinkSteps 0
		Returns the settings with shrinking disabled, whatever the configuration says.

	.EXAMPLE
		Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ MaxShrinkSteps = "many" } } }
		Warns that MaxShrinkSteps must be an integer between 0 and 50 and returns the default 10 for it.

	.EXAMPLE
		(Resolve-TerminalGreetingSettings).Onefetch
		Shows whether onefetch is on, whether it counts towards the fit, and the arguments it gets.

	.EXAMPLE
		(Resolve-TerminalGreetingSettings).Onefetch.Style
		Shows whether the panel is restyled, with what separator and which color remapping.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[hashtable]$Settings = $global:Configuration.TerminalGreeting,

		[AllowNull()]
		[nullable[int]]$MaxShrinkSteps,

		[AllowNull()]
		[nullable[int]]$ReflowTimeoutMilliseconds,

		[AllowNull()]
		[nullable[int]]$PromptReserve
	)

	# The sub-hashtable a key lives under, or $null when the section has no such branch. Written
	# as a helper rather than inline so all four branches read the same way and a branch written
	# as something other than a hashtable degrades to the defaults instead of throwing.
	$branch = {
		param([hashtable]$Parent, [string]$Name)
		if ($Parent -and $Parent.Contains($Name) -and $Parent[$Name] -is [hashtable]) { return $Parent[$Name] }
		return $null
	}

	$clearSection = & $branch $Settings "Clear"
	$fastfetchSection = & $branch $Settings "Fastfetch"
	$autoFitSection = & $branch $fastfetchSection "AutoFit"
	$onefetchSection = & $branch $Settings "Onefetch"

	# One boolean key. $null / missing is the silent "use the default"; anything else is read with
	# PowerShell's own truthiness, which handles $true / $false, 1 / 0 and a string the way a psd1
	# author would expect.
	$resolveBool = {
		param([hashtable]$Section, [string]$Key, [bool]$Default, [string]$Path)
		$value = $Default
		$source = "default"
		if ($Section -and $Section.Contains($Key) -and $null -ne $Section[$Key]) {
			$value = [bool]$Section[$Key]
			$source = "configuration"
		}
		Write-LogDebug "[Resolve-TerminalGreetingSettings] $Path = $value ($source)"
		return $value
	}

	# One integer key, validated against its range in both layers so a bad call-site value is
	# reported rather than silently accepted. A $null Maximum means no upper bound: the reflow
	# timeout is the per-machine tuning knob and a user testing a slow terminal must be free to go
	# as high as it takes.
	$resolveInt = {
		param([hashtable]$Section, [string]$Key, [hashtable]$Rule, $Override, [string]$Path)
		$value = $Rule.Default
		$source = "default"

		if ($Section -and $Section.Contains($Key) -and $null -ne $Section[$Key]) {
			$candidate = 0
			$parsed = [int]::TryParse("$($Section[$Key])", [ref]$candidate)
			if ($parsed -and $candidate -ge $Rule.Minimum -and ($null -eq $Rule.Maximum -or $candidate -le $Rule.Maximum)) {
				$value = $candidate
				$source = "configuration"
			}
			else {
				Write-LogWarning "Configuration.$Path must be $($Rule.Shape) - got [$($Section[$Key])]. Using the default [$($Rule.Default)]."
			}
		}

		if ($null -ne $Override) {
			$candidate = [int]$Override
			if ($candidate -ge $Rule.Minimum -and ($null -eq $Rule.Maximum -or $candidate -le $Rule.Maximum)) {
				$value = $candidate
				$source = "parameter"
			}
			else {
				Write-LogWarning "-$Key must be $($Rule.Shape) - got [$candidate]. Using [$value] ($source)."
			}
		}

		Write-LogDebug "[Resolve-TerminalGreetingSettings] $Path = $value ($source)"
		return $value
	}

	$rules = @{
		MaxShrinkSteps            = @{ Default = 10; Minimum = 0; Maximum = 50; Shape = "an integer between 0 and 50" }
		ReflowTimeoutMilliseconds = @{ Default = 10; Minimum = 1; Maximum = $null; Shape = "a positive integer" }
		PromptReserve             = @{ Default = 1; Minimum = 0; Maximum = 20; Shape = "an integer between 0 and 20" }
	}

	# Arguments: a single string is as valid as an array, and a missing or empty key is no arguments.
	$arguments = @()
	if ($onefetchSection -and $onefetchSection.Contains("Arguments") -and $null -ne $onefetchSection["Arguments"]) {
		$arguments = @($onefetchSection["Arguments"] |
			Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
			ForEach-Object { "$_" })
	}
	Write-LogDebug "[Resolve-TerminalGreetingSettings] TerminalGreeting.Onefetch.Arguments = [$($arguments -join ' ')]"

	# Style: a separator string and a color map, both free-form enough that there is nothing to
	# range-check here - Format-OnefetchPanel skips an index it cannot use and says so at debug
	# level, which is the right place for it, since the same map has to survive being written by
	# hand in a psd1.
	$styleSection = & $branch $onefetchSection "Style"

	$separator = ""
	if ($styleSection -and $styleSection.Contains("Separator") -and $null -ne $styleSection["Separator"]) {
		$separator = "$($styleSection["Separator"])"
	}

	$colors = @{}
	if ($styleSection -and $styleSection.Contains("Colors") -and $styleSection["Colors"] -is [hashtable]) {
		$colors = $styleSection["Colors"]
	}
	Write-LogDebug "[Resolve-TerminalGreetingSettings] TerminalGreeting.Onefetch.Style.Separator = [$separator], Colors = [$($colors.Count)]"

	return [pscustomobject]@{
		Clear     = [pscustomobject]@{
			Enabled = & $resolveBool $clearSection "Enabled" $true "TerminalGreeting.Clear.Enabled"
		}
		Fastfetch = [pscustomobject]@{
			Enabled = & $resolveBool $fastfetchSection "Enabled" $true "TerminalGreeting.Fastfetch.Enabled"
			AutoFit = [pscustomobject]@{
				Enabled                   = & $resolveBool $autoFitSection "Enabled" $true "TerminalGreeting.Fastfetch.AutoFit.Enabled"
				MaxShrinkSteps            = & $resolveInt $autoFitSection "MaxShrinkSteps" $rules.MaxShrinkSteps $MaxShrinkSteps "TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps"
				ReflowTimeoutMilliseconds = & $resolveInt $autoFitSection "ReflowTimeoutMilliseconds" $rules.ReflowTimeoutMilliseconds $ReflowTimeoutMilliseconds "TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds"
				PromptReserve             = & $resolveInt $autoFitSection "PromptReserve" $rules.PromptReserve $PromptReserve "TerminalGreeting.Fastfetch.AutoFit.PromptReserve"
			}
		}
		Onefetch  = [pscustomobject]@{
			Enabled            = & $resolveBool $onefetchSection "Enabled" $false "TerminalGreeting.Onefetch.Enabled"
			IncludeInAutoFit   = & $resolveBool $onefetchSection "IncludeInAutoFit" $true "TerminalGreeting.Onefetch.IncludeInAutoFit"
			InProjectTerminals = & $resolveBool $onefetchSection "InProjectTerminals" $true "TerminalGreeting.Onefetch.InProjectTerminals"
			Arguments          = [string[]]$arguments
			Style              = [pscustomobject]@{
				Enabled   = & $resolveBool $styleSection "Enabled" $false "TerminalGreeting.Onefetch.Style.Enabled"
				Separator = $separator
				Colors    = $colors
			}
		}
	}
}

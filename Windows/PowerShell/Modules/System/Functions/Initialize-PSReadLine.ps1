function Initialize-PSReadLine {
	<#
	.SYNOPSIS
		Applies the PSReadLine editing, history and prediction options from Configuration.PSReadLine.

	.DESCRIPTION
		Replaces the block of hardcoded Set-PSReadLineOption / Set-PSReadLineKeyHandler calls the
		profile used to carry, so every interactive option comes from one configuration section
		and a fork changes them in Configuration.local.psd1 instead of editing the shared profile.

		Every key is optional. A key set to $null (or missing) is skipped, and PSReadLine keeps
		whatever it already had - which for a vanilla install is its own default. That is also how
		a fork unbinds a base key handler: set the key to $null in KeyHandlers.

		ORDER MATTERS, and the function preserves the order the profile established:

		1. EditMode. Set-PSReadLineOption -EditMode installs that mode's ENTIRE key map, so every
		   binding made before it is silently reset. It therefore always runs first.
		2. KeyHandlers, one Set-PSReadLineKeyHandler per entry.
		3. History options: MaximumHistoryCount, HistorySavePath, HistoryNoDuplicates.
		4. PredictionSource, PredictionViewStyle and Colors, last and inside their own try/catch:
		   the prediction options throw on a console without virtual-terminal support (redirected
		   output, CI, automation hosts), the list colours throw on a PSReadLine older than the list
		   (Windows PowerShell's 2.0.0), and a cosmetic feature must never break shell startup.
		   Because they run last, everything above has already applied when they fail.

		Colors takes ListPrediction, ListPredictionSelected and Emphasis, each a colour name (black,
		red, green, yellow, blue, magenta, cyan, white, default), 0-255 or #RRGGBB, the forms
		Foundation takes. They are converted to the escape sequence PSReadLine stores, because
		PSReadLine refuses 0-255, reads red as bright red, and would turn #RRGGBB into a foreground
		colour for ListPredictionSelected, which is a background. A value of another form is
		reported with a warning and skipped; the other colours still apply.

		MaximumHistoryCount drives two limits with one number: PSReadLine's own cap (arrow-key and
		Ctrl+R recall) and the session preference variable $MaximumHistoryCount (Get-History /
		Invoke-History). PowerShell caps the variable at 32767, so that one is clamped; PSReadLine
		takes the raw value. A value that is not a positive integer is reported with a warning and
		skipped. Note that PSReadLine never trims the history FILE - it appends every command and
		loads the newest MaximumHistoryCount lines at startup - so this cap is what is recallable,
		not what is stored.

		HistorySavePath accepts environment variables in %NAME% form; the path is expanded before
		it is handed to PSReadLine.

		Reads $global:Configuration.PSReadLine by default. Called by the profile on every
		interactive shell start; the profile imports PSReadLine first and calls Initialize-OhMyPosh
		AFTER this function, because a theme with a transient prompt binds Enter, and an -EditMode
		call after that binding would reset it.

	.PARAMETER Settings
		The PSReadLine configuration section. Defaults to $global:Configuration.PSReadLine. When
		$null or empty, the function logs at debug level and does nothing.

	.EXAMPLE
		Initialize-PSReadLine
		Applies Configuration.PSReadLine to the current session (profile usage).

	.EXAMPLE
		Initialize-PSReadLine -Settings @{ MaximumHistoryCount = 32767 }
		Raises both recall limits and leaves every other option untouched.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[hashtable]$Settings = (Get-ConfigSetting -Path 'PSReadLine')
	)

	if (-not $Settings -or $Settings.Count -eq 0) {
		Write-LogDebug "Configuration.PSReadLine is empty - PSReadLine keeps its defaults."
		return
	}

	# 1. Edit mode first - it resets every key binding made before it.
	if ($null -ne $Settings.EditMode -and "$($Settings.EditMode)" -ne "") {
		Set-PSReadLineOption -EditMode $Settings.EditMode
	}

	# 2. Key handlers, sorted so the order is deterministic across runs. A $null value unbinds
	#    nothing and rebinds nothing - it is how a fork drops a base binding by omission.
	if ($Settings.KeyHandlers -is [hashtable]) {
		foreach ($key in ($Settings.KeyHandlers.Keys | Sort-Object)) {
			$handler = $Settings.KeyHandlers[$key]
			if ($null -eq $handler -or "$handler" -eq "") { continue }
			Set-PSReadLineKeyHandler -Key $key -Function $handler
		}
	}

	# 3. History options.
	if ($null -ne $Settings.MaximumHistoryCount) {
		$count = 0
		if ([int]::TryParse("$($Settings.MaximumHistoryCount)", [ref]$count) -and $count -gt 0) {
			Set-PSReadLineOption -MaximumHistoryCount $count
			# $MaximumHistoryCount (Get-History) is capped by PowerShell at 32767.
			Set-Variable -Name MaximumHistoryCount -Scope Global -Value ([Math]::Min($count, 32767))
		}
		else {
			Write-LogWarning "Configuration.PSReadLine.MaximumHistoryCount must be a positive integer - got [$($Settings.MaximumHistoryCount)]. Leaving the history limit unchanged."
		}
	}

	if ($null -ne $Settings.HistorySavePath -and "$($Settings.HistorySavePath)" -ne "") {
		$historyPath = [Environment]::ExpandEnvironmentVariables("$($Settings.HistorySavePath)")
		Set-PSReadLineOption -HistorySavePath $historyPath
	}

	if ($null -ne $Settings.HistoryNoDuplicates) {
		Set-PSReadLineOption -HistoryNoDuplicates:([bool]$Settings.HistoryNoDuplicates)
	}

	# 4. Prediction options and list colours last - the calls that throw on a console without
	#    virtual-terminal support or an old PSReadLine. Everything above has already applied by the
	#    time they do.
	try {
		if ($null -ne $Settings.PredictionSource -and "$($Settings.PredictionSource)" -ne "") {
			Set-PSReadLineOption -PredictionSource $Settings.PredictionSource
		}
		if ($null -ne $Settings.PredictionViewStyle -and "$($Settings.PredictionViewStyle)" -ne "") {
			Set-PSReadLineOption -PredictionViewStyle $Settings.PredictionViewStyle
		}

		if ($Settings.Colors -is [hashtable]) {
			$colorNames = @{ black = 0; red = 1; green = 2; yellow = 3; blue = 4; magenta = 5; cyan = 6; white = 7; default = 9 }
			$colors = @{}
			foreach ($name in @("Emphasis", "ListPrediction", "ListPredictionSelected")) {
				$value = "$($Settings.Colors[$name])"
				if ($value -eq "") { continue }

				# SGR codes: 3x is a foreground, 4x a background. Only the selected row is a background.
				$layer = if ($name -eq "ListPredictionSelected") { 4 } else { 3 }
				if ($colorNames.ContainsKey($value)) {
					$colors[$name] = "$([char]27)[$layer$($colorNames[$value])m"
				}
				elseif ($value -match '^[0-9]{1,3}$' -and [int]$value -le 255) {
					$colors[$name] = "$([char]27)[${layer}8;5;$([int]$value)m"
				}
				elseif ($value -match '^#[0-9a-f]{6}$') {
					$rgb = (1, 3, 5 | ForEach-Object { [Convert]::ToInt32($value.Substring($_, 2), 16) }) -join ";"
					$colors[$name] = "$([char]27)[${layer}8;2;${rgb}m"
				}
				else {
					Write-LogWarning "Configuration.PSReadLine.Colors.$name must be a colour name, 0-255 or #RRGGBB - got [$value]. Leaving it unchanged."
				}
			}
			if ($colors.Count -gt 0) {
				Set-PSReadLineOption -Colors $colors
			}
		}
		elseif ($null -ne $Settings.Colors) {
			Write-LogWarning "Configuration.PSReadLine.Colors must be a hashtable - got [$($Settings.Colors)]. Leaving the colours unchanged."
		}
	}
	catch {
		# Non-interactive/limited console or an old PSReadLine - keep defaults silently.
		Write-LogDebug "PSReadLine prediction options skipped (console without virtual-terminal support): $_"
	}
}

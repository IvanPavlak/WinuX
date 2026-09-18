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
		4. PredictionSource and PredictionViewStyle, last and inside their own try/catch: they are
		   the only two calls that throw on a console without virtual-terminal support (redirected
		   output, CI, automation hosts), and a cosmetic feature must never break shell startup.
		   Because they run last, everything above has already applied when they fail.

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

	# 4. Prediction options last - the only calls that throw on a console without virtual-terminal
	#    support. Everything above has already applied by the time they do.
	try {
		if ($null -ne $Settings.PredictionSource -and "$($Settings.PredictionSource)" -ne "") {
			Set-PSReadLineOption -PredictionSource $Settings.PredictionSource
		}
		if ($null -ne $Settings.PredictionViewStyle -and "$($Settings.PredictionViewStyle)" -ne "") {
			Set-PSReadLineOption -PredictionViewStyle $Settings.PredictionViewStyle
		}
	}
	catch {
		# Non-interactive/limited console - keep defaults silently.
		Write-LogDebug "PSReadLine prediction options skipped (console without virtual-terminal support): $_"
	}
}

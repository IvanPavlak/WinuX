function Get-WindowHandle {
	<#
	.SYNOPSIS
		Gets window handles for specified processes.

	.DESCRIPTION
		Retrieves window handles (HWND) for windows belonging to the specified process name or window title pattern.
		When both ProcessName and WindowTitle are provided, returns windows matching EITHER criterion (OR logic),
		providing redundancy for more robust window detection.

	.PARAMETER ProcessName
		The name of the process (without .exe extension). Supports both wildcard and regex syntax.
		Wildcard patterns (*, ?) are automatically converted to regex.
		Plain names (no special characters) use exact matching for performance.
		Examples:
		  Exact: "chrome", "WindowsTerminal"
		  Wildcard: "*chrome*", "fire*"
		  Regex: "(firefox|chrome|msedge|brave)", "^chrome$"
		Can be combined with WindowTitle for redundant searching.

	.PARAMETER WindowTitle
		Pattern to match against window titles. Supports both wildcard and regex syntax.
		Wildcard patterns (*, ?) are automatically converted to regex.
		Examples:
		  Wildcard: "*Notepad++", "*YouTube*", "Chrome - *"
		  Regex: "^Chrome", "Visual Studio Code$", ".*Firefox.*", "(?i)notepad"
		Can be combined with ProcessName for redundant searching.

	.EXAMPLE
		Get-WindowHandle -ProcessName "chrome"
		Get-WindowHandle -ProcessName "(firefox|chrome|msedge|brave)"
		Get-WindowHandle -WindowTitle "Visual Studio Code"
		Get-WindowHandle -WindowTitle "*YouTube*"
		Get-WindowHandle -WindowTitle "^Chrome.*Google"
		Get-WindowHandle -WindowTitle "(?i)notepad"
		Get-WindowHandle -ProcessName "WhatsApp" -WindowTitle ".*WhatsApp.*"
	#>
	[CmdletBinding(DefaultParameterSetName = 'All')]
	param (
		[Parameter()]
		[string]$ProcessName,

		[Parameter()]
		[string]$WindowTitle,

		[Parameter(ParameterSetName = 'All')]
		[switch]$All
	)

	# Use consolidated native types from WindowNative.cs (loaded in Window.psm1)
	# Get all windows using cached enumeration (avoids repeated EnumWindows syscalls)
	# Process names are now included in the native cache - no need for Get-Process calls
	$nativeWindows = Get-CachedWindows

	$windows = $nativeWindows

	# Convert ProcessName pattern to regex if needed (same logic as WindowTitle)
	# Plain names without special characters use exact matching for performance
	$processRegexPattern = $null
	$processIsExact = $false
	if ($ProcessName) {
		$containsProcessWildcard = $ProcessName -match '[\*\?]'

		# Check if the pattern contains any regex/wildcard special characters
		if ($ProcessName -match '[\.\[\]\(\)\{\}\+\^\$\|\\*\?]') {
			# Try to use as regex first
			try {
				$null = [regex]::new($ProcessName)
				$processRegexPattern = $ProcessName
			}
			catch {
				# If regex is invalid, try converting from wildcard pattern
				if ($ProcessName -match '^\*' -or ($containsProcessWildcard -and $ProcessName -notmatch '[\.\[\]\(\)\{\}\+\^\$\|\\]')) {
					# Convert wildcard to regex
					$processRegexPattern = [regex]::Escape($ProcessName)
					$processRegexPattern = $processRegexPattern -replace '\\\*', '.*' -replace '\\\?', '.'

					# Validate converted pattern
					try {
						$null = [regex]::new($processRegexPattern)
					}
					catch {
						Write-Error "Invalid pattern => [$ProcessName] => Could not convert to valid regex: $_"
						$processRegexPattern = $null
					}
				}
				else {
					# Process names can legally contain regex metacharacters such as +.
					# When the pattern is not valid regex and not a wildcard, treat it as an exact name.
					$processIsExact = $true
				}
			}
		}
		else {
			# Plain name without special characters - use exact matching
			$processIsExact = $true
		}
	}

	# Convert WindowTitle pattern to regex if needed
	# Detects wildcard patterns (*, ?) and converts them to regex
	$regexPattern = $null
	if ($WindowTitle) {
		# Try to use as regex first
		try {
			$null = [regex]::new($WindowTitle)
			$regexPattern = $WindowTitle
		}
		catch {
			# If regex is invalid, try converting from wildcard pattern
			# Wildcard pattern indicators: starts with *, contains * or ? without regex context
			if ($WindowTitle -match '^\*' -or ($WindowTitle -match '[\*\?]' -and $WindowTitle -notmatch '[\.\[\]\(\)\{\}\+\^\$\|\\]')) {
				# Convert wildcard to regex
				# Escape regex special chars except * and ?
				$regexPattern = [regex]::Escape($WindowTitle)
				# Convert wildcards: \* -> .* and \? -> .
				$regexPattern = $regexPattern -replace '\\\*', '.*' -replace '\\\?', '.'

				# Validate converted pattern
				try {
					$null = [regex]::new($regexPattern)
				}
				catch {
					Write-Error "Invalid pattern => [$WindowTitle] => Could not convert to valid regex: $_"
					$regexPattern = $null
				}
			}
			else {
				Write-Error "Invalid regex pattern => [$WindowTitle] => $_"
				$regexPattern = $null
			}
		}
	}

	# Helper scriptblock for process name matching (exact -eq or regex -match)
	$matchesProcessName = if ($processIsExact) {
		{ param($pn) $pn -eq $ProcessName }
	}
	elseif ($processRegexPattern) {
		{ param($pn) $pn -match $processRegexPattern }
	}
	else {
		{ param($pn) $false }
	}

	# If both ProcessName and WindowTitle are provided, use OR logic (match either)
	# This provides redundancy - if one criterion is slow/fails, the other succeeds
	if ($ProcessName -and $WindowTitle) {
		if ($regexPattern) {
			return $windows | Where-Object {
				# Match by ProcessName OR WindowTitle
				(& $matchesProcessName $_.ProcessName) -or
				(-not [string]::IsNullOrEmpty($_.Title) -and $_.Title -match $regexPattern)
			}
		}
		else {
			# Fall back to ProcessName only if title regex is invalid
			return $windows | Where-Object { & $matchesProcessName $_.ProcessName }
		}
	}
	elseif ($ProcessName) {
		return $windows | Where-Object { & $matchesProcessName $_.ProcessName }
	}
	elseif ($WindowTitle) {
		if ($regexPattern) {
			return $windows | Where-Object {
				-not [string]::IsNullOrEmpty($_.Title) -and
				$_.Title -match $regexPattern
			}
		}
		else {
			return @()
		}
	}
	else {
		return $windows
	}
}

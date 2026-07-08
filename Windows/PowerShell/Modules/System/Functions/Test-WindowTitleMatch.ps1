function Test-WindowTitleMatch {
	<#
	.SYNOPSIS
		Tests if a window/process matches any of the provided patterns.

	.DESCRIPTION
		Checks if a window title or process name matches any pattern in the provided array.
		Supports both wildcard and regex patterns, following the same pattern
		format used in window layout configurations.

		Matching logic:
		  1. Exact match against ProcessName (case-insensitive)
		  2. Pattern match against WindowTitle (wildcard or regex)

		Pattern format (same as Get-WindowHandle and layout .psd1 files):
		  Process name: "Code", "firefox", "Obsidian" (exact match)
		  Wildcard: "*YouTube*", "*Obsidian*", "Chrome - *"
		  Regex: "^Chrome", ".*Firefox.*", "(?i)notepad", "(.*Gmail.*|.*Inbox.*)"

	.PARAMETER WindowTitle
		The actual window title to test against patterns.

	.PARAMETER ProcessName
		The process name to test against patterns (optional, for exact matching).

	.PARAMETER Patterns
		Array of patterns to match against. Each pattern can be:
		- Process name: Exact match (e.g., "Code", "firefox")
		- Wildcard pattern: Uses * and ? as wildcards
		- Regex pattern: Any valid regex expression

	.OUTPUTS
		Boolean indicating if the window/process matches any of the patterns.

	.EXAMPLE
		Test-WindowTitleMatch -WindowTitle "YouTube - Google Chrome" -Patterns @("*YouTube*")
		# Returns: $true

	.EXAMPLE
		Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1 - Visual Studio Code" -Patterns @("Code")
		# Returns: $true (matches process name exactly)

	.EXAMPLE
		Test-WindowTitleMatch -WindowTitle "My Document - Word" -Patterns @("*YouTube*", "*Gmail*")
		# Returns: $false

	.EXAMPLE
		Test-WindowTitleMatch -WindowTitle "Gmail Inbox" -Patterns @("(.*Gmail.*|.*Inbox.*)")
		# Returns: $true
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter()]
		[AllowEmptyString()]
		[string]$WindowTitle,

		[Parameter()]
		[AllowEmptyString()]
		[string]$ProcessName,

		[Parameter(Mandatory)]
		[string[]]$Patterns
	)

	foreach ($pattern in $Patterns) {
		if ([string]::IsNullOrWhiteSpace($pattern)) {
			continue
		}

		# First, check for exact process name match (case-insensitive)
		if ($ProcessName -and $ProcessName -eq $pattern) {
			return $true
		}

		# Skip window title matching if no title provided
		if ([string]::IsNullOrEmpty($WindowTitle)) {
			continue
		}

		$regexPattern = $null

		# Try to use as regex first
		try {
			$null = [regex]::new($pattern)
			$regexPattern = $pattern
		}
		catch {
			# If regex is invalid, try converting from wildcard pattern
			# Wildcard pattern indicators: starts with *, contains * or ? without regex context
			if ($pattern -match '^\*' -or ($pattern -match '[\*\?]' -and $pattern -notmatch '[\.\[\]\(\)\{\}\+\^\$\|\\]')) {
				# Convert wildcard to regex
				# Escape regex special chars except * and ?
				$regexPattern = [regex]::Escape($pattern)
				# Convert wildcards: \* -> .* and \? -> .
				$regexPattern = $regexPattern -replace '\\\*', '.*' -replace '\\\?', '.'

				# Validate converted pattern
				try {
					$null = [regex]::new($regexPattern)
				}
				catch {
					# Invalid pattern, skip
					continue
				}
			}
			else {
				# Invalid pattern, skip
				continue
			}
		}

		if ($regexPattern -and $WindowTitle -match $regexPattern) {
			return $true
		}
	}

	return $false
}

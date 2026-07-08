function Find-ConfigurationSection {
	<#
	.SYNOPSIS
		Finds a named section's boundaries in Configuration.psd1.
	.DESCRIPTION
		Locates a section by name in a .psd1 file and returns its start/end line indices.
		Handles nested brackets and ignores brackets inside strings and comments.
	.PARAMETER Lines
		The file content as an array of strings.
	.PARAMETER SectionName
		The configuration section name to find (e.g., "BrowserGroups", "WorkspaceActions").
	.EXAMPLE
		$lines = Get-Content "Configuration.psd1"
		$section = Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"
		# Returns @{ StartIndex = 1829; EndIndex = 2050; Indent = "`t"; BracketType = "(" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[string[]]$Lines,

		[Parameter(Mandatory)]
		[string]$SectionName
	)

	$startIndex = -1
	$bracketType = ''
	$indent = ''

	for ($i = 0; $i -lt $Lines.Count; $i++) {
		if ($Lines[$i] -match "^(\s*)$([regex]::Escape($SectionName))\s+=\s+@([{(])") {
			$startIndex = $i
			$indent = $Matches[1]
			$bracketType = $Matches[2]
			break
		}
	}

	if ($startIndex -eq -1) { return $null }

	$openChar = if ($bracketType -eq '{') { [char]'{' } else { [char]'(' }
	$closeChar = if ($bracketType -eq '{') { [char]'}' } else { [char]')' }
	$depth = 0

	for ($i = $startIndex; $i -lt $Lines.Count; $i++) {
		$stripped = $Lines[$i] -replace "'[^']*'", "''" -replace '"[^"]*"', '""' -replace '#.*$', ''

		foreach ($c in $stripped.ToCharArray()) {
			if ($c -eq $openChar) { $depth++ }
			elseif ($c -eq $closeChar) {
				$depth--
				if ($depth -eq 0) {
					return @{
						StartIndex  = $startIndex
						EndIndex    = $i
						Indent      = $indent
						BracketType = [string]$bracketType
					}
				}
			}
		}
	}

	return $null
}

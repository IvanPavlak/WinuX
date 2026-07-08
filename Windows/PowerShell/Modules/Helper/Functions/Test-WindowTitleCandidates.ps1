function Test-WindowTitleCandidates {
	<#
	.SYNOPSIS
		Check if window title matches any candidate patterns.

	.DESCRIPTION
		Performs case-insensitive regex matching of window title against multiple candidate strings.
		Used for robust window detection in automation tasks.

	.PARAMETER WindowTitle
		The actual window title to test.

	.PARAMETER Candidates
		Array of candidate strings to match against (supports regex escaping).

	.EXAMPLE
		if (Test-WindowTitleCandidates -WindowTitle "VS Code - MyProject" -Candidates @("MyProject", "Code")) { Write-Host "Found window" }
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$WindowTitle,

		[Parameter()]
		[string[]]$Candidates
	)

	foreach ($candidate in $Candidates) {
		if (-not [string]::IsNullOrWhiteSpace($candidate) -and $WindowTitle -match "(?i)$([regex]::Escape($candidate))") {
			return $true
		}
	}

	return $false
}

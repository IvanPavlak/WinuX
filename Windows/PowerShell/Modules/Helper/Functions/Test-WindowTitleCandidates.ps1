function Test-WindowTitleCandidates {
	<#
	.SYNOPSIS
		Check if window title matches any candidate patterns.

	.DESCRIPTION
		Checks case-insensitively whether any candidate is a whole " - " separated segment of the
		window title, so "MyApp" matches "Program.cs - MyApp - Visual Studio Code" but not
		"myapp-ui - Visual Studio Code". A leading VS Code dirty marker is ignored, and for Visual
		Studio ("devenv") a candidate may be followed by a debugger state such as " (Debugging)".
		Used for robust window detection in automation tasks.

	.PARAMETER WindowTitle
		The actual window title to test.

	.PARAMETER Candidates
		Array of candidate strings to match against (regex-escaped, so matched literally).

	.PARAMETER ProcessName
		The process that owns the window. "devenv" allows Visual Studio's debugger state after a
		candidate; any other value, or none, requires the bare segment.

	.EXAMPLE
		if (Test-WindowTitleCandidates -WindowTitle "Program.cs - MyProject - Visual Studio Code" -Candidates @("MyProject", "MyRepo")) { Write-Host "Found window" }

	.EXAMPLE
		Test-WindowTitleCandidates -WindowTitle "MySolution (Debugging) - Microsoft Visual Studio" -Candidates @("MySolution") -ProcessName "devenv"
		Returns `$true`.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter()]
		[string]$WindowTitle,

		[Parameter()]
		[string[]]$Candidates,

		[Parameter()]
		[string]$ProcessName
	)

	# Visual Studio appends the debugger state to the solution segment
	# ("MySolution (Debugging) - Microsoft Visual Studio")
	$stateSuffix = if ($ProcessName -eq "devenv") { '(?: \([^()]+\))?' } else { '' }

	foreach ($candidate in $Candidates) {
		if ([string]::IsNullOrWhiteSpace($candidate)) {
			continue
		}

		# The candidate must fill a whole " - " separated title segment, so "MyApp" is not matched by
		# the "myapp-ui - Visual Studio Code" window. The first segment may start with VS Code's dirty
		# marker (U+25CF and a space).
		$titlePattern = '(?i)(?:^(?:\u25CF )?| - )' + [regex]::Escape($candidate) + $stateSuffix + '(?: - |$)'

		if ($WindowTitle -match $titlePattern) {
			return $true
		}
	}

	return $false
}

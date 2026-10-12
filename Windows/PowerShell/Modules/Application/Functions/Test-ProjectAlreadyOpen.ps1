function Test-ProjectAlreadyOpen {
	<#
    .SYNOPSIS
        Checks whether a project is already open in a given application by matching window titles.

    .DESCRIPTION
        Gets all window handles for the specified process name and checks, through
        Test-WindowTitleCandidates, whether any window title has the project name as a whole
        " - " separated segment (case-insensitive), so "MyApp" is not matched by a
        "myapp-ui - Visual Studio Code" window. A leading VS Code dirty marker is ignored, and for
        Visual Studio ("devenv") the segment may carry a debugger state such as " (Debugging)".
        Returns `$true` if a match is found and prints a yellow warning message. Returns `$false`
        if no match is found.

    .PARAMETER ProjectName
        The project name to search for in window titles. It must equal a whole title segment
        (e.g. the folder name in "file.ps1 - MyApp - Visual Studio Code").

    .PARAMETER ProcessName
        The process name of the application to check (e.g. "devenv" for Visual Studio).

    .PARAMETER ApplicationName
        Human-readable application name used in the warning message.

    .EXAMPLE
        Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "devenv" -ApplicationName "Visual Studio"
        Returns `$true` and prints a warning if Visual Studio has MyApp open.
    #>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$ProjectName,

		[Parameter(Mandatory)]
		[string]$ProcessName,

		[Parameter(Mandatory)]
		[string]$ApplicationName
	)

	try {
		$windows = Get-WindowHandle -ProcessName $ProcessName -ErrorAction SilentlyContinue

		if (-not $windows) {
			return $false
		}

		foreach ($window in $windows) {
			if (Test-WindowTitleCandidates -WindowTitle $window.Title -Candidates @($ProjectName) -ProcessName $ProcessName) {
				Write-LogWarning "$ApplicationName with project [$ProjectName] is already open!"
				return $true
			}
		}

		return $false
	}
	catch {
		return $false
	}
}

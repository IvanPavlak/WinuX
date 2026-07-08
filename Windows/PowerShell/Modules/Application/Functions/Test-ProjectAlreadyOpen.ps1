function Test-ProjectAlreadyOpen {
	<#
    .SYNOPSIS
        Checks whether a project is already open in a given application by matching window titles.

    .DESCRIPTION
        Gets all window handles for the specified process name and checks whether any window
        title contains the project name. Returns `$true` if a match is found and prints a
        yellow warning message. Returns `$false` if no match is found.

    .PARAMETER ProjectName
        The project name to search for in window titles.

    .PARAMETER ProcessName
        The process name of the application to check (e.g. "devenv" for Visual Studio).

    .PARAMETER ApplicationName
        Human-readable application name used in the warning message.

    .EXAMPLE
        Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "devenv" -ApplicationName "Visual Studio"
        Returns `$true` and prints a warning if Visual Studio has MyApp open.
    #>
	[CmdletBinding()]
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
			if ($window.Title -match "(?i)$([regex]::Escape($ProjectName))") {
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

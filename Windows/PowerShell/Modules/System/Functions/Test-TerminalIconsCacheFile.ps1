function Test-TerminalIconsCacheFile {
	<#
	.SYNOPSIS
		Reports whether one Terminal-Icons theme cache file parses as Clixml.

	.DESCRIPTION
		Reads the file with Import-Clixml, the way Terminal-Icons reads it on import, and returns
		$true when that succeeds. Never throws: a file that fails to parse, has vanished or cannot
		be read returns $false, with the reason passed back through -Reason when the caller asks
		for it. Repair-TerminalIconsThemeCache calls it twice per suspect file - once to find the
		file, once after a short pause to tell a torn file from one another shell is still writing.

	.PARAMETER Path
		The cache file to read.

	.PARAMETER Reason
		Receives the parse error's message when the file does not parse; left alone when it does.

	.OUTPUTS
		[bool] - $true when the file parses.

	.EXAMPLE
		Test-TerminalIconsCacheFile -Path "$env:APPDATA\powershell\Community\Terminal-Icons\prefs.xml"
		$true for a healthy cache file.

	.EXAMPLE
		$reason = $null; if (-not (Test-TerminalIconsCacheFile -Path $file -Reason ([ref]$reason))) { $reason }
		Prints why a file does not parse.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Path,

		[Parameter()]
		[ref]$Reason
	)

	try {
		$null = Import-Clixml -LiteralPath $Path -ErrorAction Stop
		return $true
	}
	catch {
		if ($Reason) { $Reason.Value = $_.Exception.Message }
		return $false
	}
}

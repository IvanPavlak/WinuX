function Test-TerminalIconsCacheFile {
	<#
	.SYNOPSIS
		Reports whether one Terminal-Icons theme cache file is readable the way the module reads it.

	.DESCRIPTION
		Reads the file with Import-Clixml, the way Terminal-Icons reads it on import, and returns
		$true when that succeeds and the content is whole. A torn file does not always fail to
		parse: when two shells write the same file at once, each orders its hashtable keys
		differently, and their writes can splice into well-formed XML whose second half repeats
		objects of the first. Such a file parses, but a table the module indexes comes back
		missing and the import fails with "Cannot index into a null array". So two more checks
		run on a file that parses: no object RefId may appear twice (Export-Clixml numbers every
		object once, so a repeat is the splice), and a theme file (*_color.xml, *_icon.xml) must
		carry the Types.Directories and Types.Files tables the module reads.

		Never throws: a file that fails any check, has vanished or cannot be read returns $false,
		with the reason passed back through -Reason when the caller asks for it.
		Repair-TerminalIconsThemeCache calls it twice per suspect file - once to find the file,
		once after a short pause to tell a torn file from one another shell is still writing.

	.PARAMETER Path
		The cache file to read.

	.PARAMETER Reason
		Receives why the file is unreadable when it is; left alone when it is readable.

	.OUTPUTS
		[bool] - $true when the file parses and is whole.

	.EXAMPLE
		Test-TerminalIconsCacheFile -Path "$env:APPDATA\powershell\Community\Terminal-Icons\prefs.xml"
		$true for a healthy cache file.

	.EXAMPLE
		$reason = $null; if (-not (Test-TerminalIconsCacheFile -Path $file -Reason ([ref]$reason))) { $reason }
		Prints why a file is unreadable.
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

	$problem = $null
	try {
		$content = Import-Clixml -LiteralPath $Path -ErrorAction Stop
		$text = [System.IO.File]::ReadAllText($Path)

		$repeated = [regex]::Matches($text, '<Obj\b[^>]*\bRefId="(\d+)"') |
			Group-Object -Property { $_.Groups[1].Value } |
			Where-Object Count -GT 1 |
			Select-Object -First 1
		if ($repeated) {
			$problem = "object RefId [$($repeated.Name)] appears [$($repeated.Count)] times - two writes were spliced"
		}
		elseif ((Split-Path -Path $Path -Leaf) -match '_(color|icon)\.xml$') {
			$types = if ($content -is [System.Collections.IDictionary]) { $content['Types'] }
			foreach ($table in "Directories", "Files") {
				if (-not ($types -is [System.Collections.IDictionary] -and $types[$table] -is [System.Collections.IDictionary])) {
					$problem = "theme has no Types.$table table"
					break
				}
			}
		}
	}
	catch {
		$problem = $_.Exception.Message
	}

	if ($null -eq $problem) {
		return $true
	}
	if ($Reason) { $Reason.Value = $problem }
	return $false
}

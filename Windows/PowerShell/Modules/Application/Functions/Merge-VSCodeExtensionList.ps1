function Merge-VSCodeExtensionList {
	<#
	.SYNOPSIS
		Merges the extensions a VS Code profile has installed into the lines of its extensions.txt, keeping comments and pins.

	.DESCRIPTION
		The capture side of extensions.txt (Export-VSCodeProfile). Rewriting the file from
		`code --list-extensions` would drop every comment that says why an extension is there
		and every version pin, so the existing lines are merged instead:

		- Blank and comment lines are kept where they are.
		- An entry whose extension is still installed is kept exactly as written, pin and
		  trailing comment included.
		- An entry whose extension is no longer installed is removed.
		- Installed extensions the file does not name yet are appended, sorted.

		Ids are compared case-insensitively, and an extension listed twice keeps its first
		line. The result is the new list of lines, emitted one by one (wrap the call in @(...)
		for an array); nothing is written here.

	.PARAMETER Lines
		The current lines of extensions.txt. Empty for a profile captured for the first time.

	.PARAMETER Installed
		The extension ids the profile has installed (`code --list-extensions` output). A
		trailing @version is ignored.

	.EXAMPLE
		$lines = @(Merge-VSCodeExtensionList -Lines (Get-Content extensions.txt) -Installed (& code --list-extensions))
		Set-Content extensions.txt $lines
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter()]
		[AllowEmptyCollection()]
		[AllowEmptyString()]
		[string[]]$Lines = @(),

		[Parameter()]
		[AllowEmptyCollection()]
		[string[]]$Installed = @()
	)

	$installedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($id in $Installed) {
		$clean = ([string]$id -split '@', 2)[0].Trim()
		if ($clean) { $installedIds.Add($clean) | Out-Null }
	}

	$listed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$merged = [System.Collections.Generic.List[string]]::new()
	foreach ($line in @($Lines)) {
		$entry = ConvertFrom-VSCodeExtensionLine -Line ([string]$line)
		if (-not $entry) {
			$merged.Add([string]$line)
			continue
		}
		if ($installedIds.Contains($entry.Id) -and $listed.Add($entry.Id)) {
			$merged.Add([string]$line)
		}
	}

	foreach ($id in ($installedIds | Sort-Object)) {
		if ($listed.Add($id)) {
			$merged.Add($id)
		}
	}

	return $merged.ToArray()
}

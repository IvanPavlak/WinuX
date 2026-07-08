function Expand-Hashtable {
	<#
	.SYNOPSIS
		Recursively expands placeholder tokens in hashtable values.

	.DESCRIPTION
		Walks a hashtable (or array/string/list) and replaces all placeholder tokens:
		- {Dev} → development path
		- {User} → user path
		- {MachineType} → machine type name
		- {RepoRoot} → WinuX repository root
		- {AppData} → AppData directory

		Works recursively on nested hashtables and arrays. Non-placeholdertokens are passed through unchanged.
		Used internally by Expand-ConfigPaths; rarely called directly.

	.PARAMETER Source
		The hashtable/array/value to expand. Can be nested.

	.PARAMETER DevPath
		The development directory path to substitute for {Dev}.

	.PARAMETER UserPath
		The user directory path to substitute for {User}.

	.PARAMETER MachineTypeName
		The machine type name to substitute for {MachineType}.

	.PARAMETER RepoRoot
		WinuX repository root, supplied by Load-PathConfiguration (self-located at runtime). A legacy
		fallback to derive it from Source.Projects.Self.Root remains, but no longer resolves because
		that key is now "{RepoRoot}" itself; supply this parameter to expand {RepoRoot} tokens.

	.EXAMPLE
		$expanded = Expand-Hashtable -Source $config -DevPath "C:\\dev" -UserPath "C:\\Users\\You" -MachineTypeName "PC"
		Expands all placeholder tokens in the config hashtable.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		$Source,

		[Parameter(Mandatory = $true)]
		[string]$DevPath,

		[Parameter(Mandatory = $true)]
		[string]$UserPath,

		[Parameter(Mandatory = $true)]
		[string]$MachineTypeName,

		[Parameter(Mandatory = $false)]
		[string]$RepoRoot = $null
	)

	if (-not $RepoRoot -and $Source -is [hashtable] -and $Source.ContainsKey('Projects') -and $Source.Projects.ContainsKey('Self') -and $Source.Projects.Self.ContainsKey('Root')) {
		# Legacy fallback for callers that do not supply -RepoRoot. Since the repo root is now
		# self-located (Projects.Self.Root is itself "{RepoRoot}"), this derivation can no longer
		# yield a usable path - only accept it when it resolved to a real value, otherwise leave the token
		# untouched so the omission fails visibly rather than silently expanding to a self-referential literal.
		$derived = $Source.Projects.Self.Root.Replace('{Dev}', $DevPath)
		if (-not $derived.Contains('{RepoRoot}')) { $RepoRoot = $derived }
	}

	if ($null -eq $Source) {
		return $null
	}

	if ($Source -is [hashtable]) {
		$result = @{}
		foreach ($key in $Source.Keys) {
			$value = $Source[$key]
			if ($null -ne $value) {
				$result[$key] = Expand-Hashtable -Source $value -DevPath $DevPath -UserPath $UserPath -MachineTypeName $MachineTypeName -RepoRoot $RepoRoot
			}
			else {
				$result[$key] = $null
			}
		}
		return $result
	}
	elseif ($Source -is [System.Collections.IList]) {
		$result = @()
		foreach ($item in $Source) {
			if ($null -ne $item) {
				$result += Expand-Hashtable -Source $item -DevPath $DevPath -UserPath $UserPath -MachineTypeName $MachineTypeName -RepoRoot $RepoRoot
			}
			else {
				$result += $null
			}
		}
		return $result
	}
	elseif ($Source -is [string]) {
		$expanded = $Source.Replace('{Dev}', $DevPath).Replace('{User}', $UserPath).Replace('{MachineType}', $MachineTypeName)
		$expanded = $expanded.Replace('{AppData}', $env:APPDATA).Replace('%APPDATA%', $env:APPDATA)
		$expanded = $expanded.Replace('%ALLUSERSPROFILE%', $env:ALLUSERSPROFILE).Replace('%LOCALAPPDATA%', $env:LOCALAPPDATA)
		if ($RepoRoot) {
			$expanded = $expanded.Replace('{RepoRoot}', $RepoRoot)
		}

		# Convert Windows paths to WSL paths if the original string contains forward slashes
		if ($Source -match '/' -and $expanded -match '^[A-Za-z]:\\') {
			$driveLetter = $expanded.Substring(0, 1).ToLower()
			$pathPart = $expanded.Substring(2).Replace('\', '/')
			$expanded = "/mnt/$driveLetter$pathPart"
		}

		return $expanded
	}
	else {
		return $Source
	}
}

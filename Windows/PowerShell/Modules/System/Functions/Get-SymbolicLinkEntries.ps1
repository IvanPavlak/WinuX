function Get-SymbolicLinkEntries {
	<#
	.SYNOPSIS
		Flattens the SymbolicLinks configuration into a list of link entries.

	.DESCRIPTION
		Walks a (possibly nested) SymbolicLinks hashtable recursively and returns one
		object per leaf entry (a hashtable carrying Path and Target keys):
		- Key     : the entry's own key (e.g. "Settings")
		- FullKey : the dotted path from the root (e.g. "PowerToys.Settings")
		- Path    : where the link is created
		- Target  : what the link points to
		- IsWSL   : $true when Path or Target contains a forward slash

		Optionally selects a subset via -Scope (Windows/WSL flavor) and -Name (wildcard
		key match). Pure discovery and selection - nothing is created or touched; the
		consumer (SymbolicLinkMaker) does the linking.

	.PARAMETER SymbolicLinks
		The SymbolicLinks hashtable (normally MachineSpecificPaths.SymbolicLinks).

	.PARAMETER Scope
		Which link flavor to return: All (default), Windows (backslash paths only),
		or WSL (forward-slash paths only).

	.PARAMETER Name
		Wildcard patterns matched against each entry's bare keys and dotted paths at
		every level, so "PowerToys" selects everything beneath that group,
		"PowerToys.Settings" one nested entry, and "WSL*" every match at any level.
		Omit to return all entries.

	.EXAMPLE
		Get-SymbolicLinkEntries -SymbolicLinks $MachineSpecificPaths.SymbolicLinks

	.EXAMPLE
		Get-SymbolicLinkEntries -SymbolicLinks $MachineSpecificPaths.SymbolicLinks -Scope WSL

	.EXAMPLE
		Get-SymbolicLinkEntries -SymbolicLinks $MachineSpecificPaths.SymbolicLinks -Name "PowerToys", "FastFetch*"
	#>
	param(
		[Parameter(Mandatory)]
		[hashtable]$SymbolicLinks,

		[ValidateSet("All", "Windows", "WSL")]
		[string]$Scope = "All",

		[string[]]$Name
	)

	$entries = [System.Collections.Generic.List[pscustomobject]]::new()

	$walk = {
		param (
			[hashtable]$Node,
			[string]$Parent = ""
		)

		foreach ($key in $Node.Keys) {
			$item = $Node[$key]

			if ($item -is [hashtable] -and $item.ContainsKey("Path") -and $item.ContainsKey("Target")) {
				$entries.Add([pscustomobject]@{
						Key     = $key
						FullKey = "$($Parent)$key"
						Path    = $item.Path
						Target  = $item.Target
						IsWSL   = ($item.Path -match '/') -or ($item.Target -match '/')
					})
			}
			elseif ($item -is [hashtable]) {
				& $walk -Node $item -Parent "$($Parent)$key."
			}
		}
	}
	& $walk -Node $SymbolicLinks

	$selected = foreach ($entry in $entries) {
		if (($Scope -eq "Windows" -and $entry.IsWSL) -or ($Scope -eq "WSL" -and -not $entry.IsWSL)) {
			continue
		}

		if ($Name) {
			# A pattern selects an entry when it hits the bare key or the dotted path at
			# ANY level, so a matched group carries down to everything beneath it.
			$segments = $entry.FullKey -split '\.'
			$candidates = [System.Collections.Generic.List[string]]::new()
			$prefix = ""
			foreach ($segment in $segments) {
				$prefix = if ($prefix) { "$prefix.$segment" } else { $segment }
				$candidates.Add($segment)
				$candidates.Add($prefix)
			}

			$matched = $false
			foreach ($pattern in $Name) {
				if (@($candidates | Where-Object { $_ -like $pattern }).Count -gt 0) {
					$matched = $true
					break
				}
			}
			if (-not $matched) {
				continue
			}
		}

		$entry
	}

	return @($selected)
}

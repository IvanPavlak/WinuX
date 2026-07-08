function ConvertTo-ActionString {
	<#
	.SYNOPSIS
		Converts an action hashtable to a Configuration.psd1 entry string.
	.DESCRIPTION
		Formats an action hashtable as a properly formatted string for
		insertion into WorkspaceActions or ProjectActions sections.
	.PARAMETER Action
		The action hashtable with Action and optional Parameters keys.
	.PARAMETER Indent
		The indentation prefix for the output string.
	.EXAMPLE
		ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } } -Indent "`t`t`t"
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[hashtable]$Action,

		[Parameter(Mandatory)]
		[string]$Indent
	)

	$str = "$Indent@{ Action = `"$($Action.Action)`""

	if ($Action.Parameters -and $Action.Parameters.Count -gt 0) {
		$paramParts = @()
		foreach ($key in $Action.Parameters.Keys) {
			$val = $Action.Parameters[$key]
			if ($val -is [array]) {
				$quoted = ($val | ForEach-Object { "`"$_`"" }) -join ", "
				$paramParts += "$key = @($quoted)"
			}
			elseif ($val -is [bool]) {
				$boolVal = if ($val) { '$true' } else { '$false' }
				$paramParts += "$key = $boolVal"
			}
			else {
				$paramParts += "$key = `"$val`""
			}
		}
		$str += "; Parameters = @{ $($paramParts -join '; ') }"
	}

	$str += " }"
	return $str
}

function Merge-Hashtable {
	<#
	.SYNOPSIS
		Recursively merges overrides into a target hashtable.

	.DESCRIPTION
		Applies override values to a target hashtable, recursively merging nested hashtables.
		If both target and override keys contain hashtables, they are merged recursively.
		Otherwise, the override value replaces the target value.

		Used by Expand-ConfigPaths to apply machine-specific configuration overrides.

	.PARAMETER Target
		The target hashtable to modify (by reference).

	.PARAMETER Overrides
		The overrides hashtable containing values to merge into target.

	.EXAMPLE
		$config = @{ Dev = "C:\\dev"; Projects = @{ Path = "C:\\p" } }
		$overrides = @{ Projects = @{ Path = "D:\\p" } }
		Merge-Hashtable -Target $config -Overrides $overrides
		# $config now has Dev = "C:\\dev", Projects.Path = "D:\\p" (deeply merged)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Target,

		[Parameter(Mandatory = $true)]
		[hashtable]$Overrides
	)

	foreach ($key in $Overrides.Keys) {
		if ($Target.ContainsKey($key) -and $Target[$key] -is [hashtable] -and $Overrides[$key] -is [hashtable]) {
			Merge-Hashtable -Target $Target[$key] -Overrides $Overrides[$key]
		}
		else {
			$Target[$key] = $Overrides[$key]
		}
	}
}

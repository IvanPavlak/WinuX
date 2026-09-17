function Resolve-RepositoryUpdateScope {
	<#
	.SYNOPSIS
		Resolves which repository groups Bootstrap updates on this machine.

	.DESCRIPTION
		Reads `BootstrapConfig.RepositoryUpdateScope`: a per-machine-type hashtable whose value
		for `$global:MachineType` wins, falling back to `Default`, falling back to "All" when
		the key is absent entirely. A fork that configures nothing therefore pulls every
		repository it defines.

		The value is either "All" (case-insensitive) or one or more group names, written as a
		comma-separated string ("Work, Private") or as an array (@("Work", "Private")). Group
		names are not validated here - nothing in Bootstrap knows what groups a fork defines;
		an unknown name surfaces from `Update-Repositories -Group`, which lists the configured
		groups and updates nothing.

		Whether the step runs at all is a separate question, answered by
		`BootstrapConfig.Steps.RepositoryUpdate` (opt-in, default off) like every other
		Bootstrap step.

	.OUTPUTS
		Hashtable: All (bool), Groups (string[]). Groups is empty when All is true.

	.EXAMPLE
		Resolve-RepositoryUpdateScope
		@{ All = $true; Groups = @() } on the default configuration.

	.EXAMPLE
		Resolve-RepositoryUpdateScope
		@{ All = $false; Groups = @("Work", "Private") } when the machine's scope is "Work, Private".
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param()

	$scopeMap = $global:Configuration.BootstrapConfig.RepositoryUpdateScope

	$scopeValue = if ($scopeMap -and $scopeMap[$global:MachineType]) {
		$scopeMap[$global:MachineType]
	}
	elseif ($scopeMap -and $scopeMap.Default) {
		$scopeMap.Default
	}
	else {
		"All"
	}

	# A string may carry several groups; an array carries them already separated.
	$groups = @()
	foreach ($entry in @($scopeValue)) {
		foreach ($name in ([string]$entry).Split(',')) {
			$trimmed = $name.Trim()
			if (-not [string]::IsNullOrWhiteSpace($trimmed)) { $groups += $trimmed }
		}
	}

	# "All" is only "all repositories" when it stands alone - a fork is free to name a group
	# something that merely contains the word. A value that names nothing at all means the
	# same thing as the absent key.
	if ($groups.Count -eq 0 -or ($groups.Count -eq 1 -and $groups[0] -eq "All")) {
		return @{ All = $true; Groups = @() }
	}

	return @{ All = $false; Groups = $groups }
}

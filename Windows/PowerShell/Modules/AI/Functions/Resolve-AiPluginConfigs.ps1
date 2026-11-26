function Resolve-AiPluginConfigs {
	<#
	.SYNOPSIS
		Resolves the plugin options of AiMarketplaces for one machine type: PluginConfigs with the matching MachinePluginConfigs rows merged over it.

	.DESCRIPTION
		AiMarketplaces.PluginConfigs holds the options every machine seeds for its Claude Code
		plugins. AiMarketplaces.MachinePluginConfigs is the MachineOverrides idea applied to
		them: PluginConfigs is the default, a row is the difference for some machine types.

		    MachinePluginConfigs = @{
		        "PC"          = @{ "my-plugin" = @{ options = @{ theme = "light" } } }
		        "Laptop/Work" = @{ "my-plugin" = @{ options = @{ pulse = $null } } }
		    }

		A row key is the machine-scope string Test-MachineTypeScope understands: "All", one
		machine type, or several separated by "/". Every row whose key covers the machine type
		is deep-merged over a COPY of PluginConfigs (nested hashtables merge key by key,
		everything else is replaced), the "All" row first, then the remaining matching rows in
		alphabetical key order (a psd1 hashtable keeps no order). A value set to $null by a row
		is REMOVED, so a machine can drop an option as well as change it. A row may name a
		plugin PluginConfigs does not carry: that plugin then has options on those machines only.

		The configuration itself is never modified. An unknown machine type in a row key is
		reported by Test-MachineTypeScope with the valid values and the row never applies; a
		MachinePluginConfigs that is not a hashtable and a row that is not one are reported
		through Write-LogError and ignored, so a typo cannot silently change or keep an option.

		Without MachinePluginConfigs the result is a copy of PluginConfigs, so a configuration
		that never names the key behaves as before. Deploy-AiMarketplaces writes the result to
		the settings files, on Windows and inside WSL alike.

	.PARAMETER MachineType
		The machine type the row keys are matched against. Defaults to $global:MachineType (set
		by Load-PathConfiguration / DetermineMachineType).

	.OUTPUTS
		A hashtable keyed by plugin name, each value the plugin's resolved configuration. Empty
		when neither key names a plugin.

	.EXAMPLE
		Resolve-AiPluginConfigs
		The plugin options this machine seeds.

	.EXAMPLE
		(Resolve-AiPluginConfigs -MachineType Work).'my-plugin'.options
		The options of one plugin as another machine type resolves them, without touching the live machine.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[string]$MachineType = $global:MachineType
	)

	$section = Get-ConfigSetting -Path 'AiMarketplaces'
	if ($section -isnot [hashtable]) { $section = @{} }

	# Copies hashtables and lists all the way down, so the merge below can never reach into the
	# configuration's own nested hashtables.
	$copyDeep = {
		param($Value)
		if ($Value -is [System.Collections.IDictionary]) {
			$copy = @{}
			foreach ($key in $Value.Keys) { $copy[$key] = & $copyDeep $Value[$key] }
			return $copy
		}
		if ($Value -is [System.Collections.IList] -and -not ($Value -is [string])) {
			$items = @(foreach ($item in $Value) { , (& $copyDeep $item) })
			return , $items
		}
		return $Value
	}

	# Merge-Hashtable's rule (hashtables merge key by key, everything else replaces) with copied
	# override values, plus one more: $null from a row means "not on this machine".
	$mergeInto = {
		param([hashtable]$Target, $Overrides)
		foreach ($key in $Overrides.Keys) {
			if ($null -eq $Overrides[$key]) {
				$Target.Remove($key)
			}
			elseif ($Target.ContainsKey($key) -and $Target[$key] -is [System.Collections.IDictionary] -and $Overrides[$key] -is [System.Collections.IDictionary]) {
				& $mergeInto $Target[$key] $Overrides[$key]
			}
			else {
				$Target[$key] = & $copyDeep $Overrides[$key]
			}
		}
	}

	$resolved = if ($section.PluginConfigs -is [hashtable]) { & $copyDeep $section.PluginConfigs } else { @{} }

	$table = $section.MachinePluginConfigs
	if ($null -eq $table) { return $resolved }

	$context = "AiMarketplaces.MachinePluginConfigs"
	if ($table -isnot [System.Collections.IDictionary]) {
		Write-LogError "$context must be a hashtable of machine scope => plugin options (got [$($table.GetType().Name)]) - ignored!"
		return $resolved
	}

	# "All" first, then the other rows in alphabetical order, so the result does not depend on the
	# order a hashtable happens to enumerate in.
	$keys = @($table.Keys | ForEach-Object { [string]$_ })
	$allRows = @($keys | Where-Object { $_.Trim() -eq 'All' })
	$otherRows = @($keys | Where-Object { $_.Trim() -ne 'All' })
	if ($otherRows.Count -gt 1) { [Array]::Sort($otherRows, [System.StringComparer]::OrdinalIgnoreCase) }

	foreach ($rowKey in @($allRows + $otherRows)) {
		if (-not (Test-MachineTypeScope -Scope $rowKey -MachineType $MachineType -Context $context)) { continue }

		$row = $table[$rowKey]
		if ($row -isnot [System.Collections.IDictionary]) {
			$rowType = if ($null -eq $row) { 'null' } else { $row.GetType().Name }
			Write-LogError "$context row [$rowKey] must be a hashtable of plugin options (got [$rowType]) - ignored!"
			continue
		}

		& $mergeInto $resolved $row
		Write-LogDebug " [Resolve-AiPluginConfigs] $context [$rowKey] applied on [$MachineType] => $(@($row.Keys) -join ', ')" -Style Success
	}

	return $resolved
}

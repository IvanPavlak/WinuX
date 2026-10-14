function New-ContractBaseline {
	<#
	.SYNOPSIS
		Builds the contract baseline for a release from the working tree's snapshot, keeping the
		deprecation records that still apply.

	.DESCRIPTION
		The baseline is what Test-ContractCompatibility holds every later change to: the snapshot
		(Get-ContractSnapshot) stamped with the release's version, plus the Deprecated map - item to
		the version that deprecated it, under Functions, Parameters and ConfigurationKeys.

		The Deprecated map is maintained by hand: a change that deprecates an item adds it there,
		with the version the deprecation ships in. This function carries those records forward and
		drops the ones the release has made moot - an item that was part of the previous baseline's
		contract and is gone from the new snapshot was removed in this release. A record for an item
		the snapshot cannot see (a configuration key the code still honors but the shipped
		Configuration.psd1 no longer lists) is kept.

	.PARAMETER Snapshot
		The working tree's snapshot.

	.PARAMETER Version
		The release the baseline is taken at - the newest released version in CHANGELOG.md.

	.PARAMETER Previous
		The previous baseline as read from ContractBaseline.json, or $null for the first one.

	.OUTPUTS
		[System.Collections.Specialized.OrderedDictionary] - Version, Functions, Aliases,
		ConfigurationKeys and Deprecated, ready for ConvertTo-Json.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$Snapshot,

		[Parameter(Mandatory = $true)]
		[string]$Version,

		[Parameter()]
		[AllowNull()]
		[object]$Previous
	)

	$deprecated = [ordered]@{
		Functions         = [ordered]@{}
		Parameters        = [ordered]@{}
		ConfigurationKeys = [ordered]@{}
	}

	if ($Previous -and $Previous.Deprecated) {
		$previousFunctions = @($Previous.Functions.PSObject.Properties.Name)
		$previousKeys = @($Previous.ConfigurationKeys)
		$currentNames = @($Snapshot.Functions.Keys) + @($Snapshot.Aliases)

		foreach ($kind in 'Functions', 'Parameters', 'ConfigurationKeys') {
			$records = $Previous.Deprecated.$kind
			if (-not $records) { continue }
			foreach ($record in ($records.PSObject.Properties | Sort-Object Name)) {
				$item = $record.Name
				$removed = switch ($kind) {
					'Functions' { ($previousFunctions -contains $item) -and ($currentNames -notcontains $item) }
					'ConfigurationKeys' { ($previousKeys -contains $item) -and (@($Snapshot.ConfigurationKeys) -notcontains $item) }
					'Parameters' {
						$function, $parameter = $item -split ' -', 2
						$wasThere = ($previousFunctions -contains $function) -and ($null -ne $Previous.Functions.$function.Parameters.$parameter)
						$isThere = $Snapshot.Functions.Contains($function) -and $Snapshot.Functions[$function].Parameters.Contains($parameter)
						$wasThere -and -not $isThere
					}
				}
				if (-not $removed) { $deprecated[$kind][$item] = [string]$record.Value }
			}
		}
	}

	return [ordered]@{
		Version           = $Version
		Functions         = $Snapshot.Functions
		Aliases           = $Snapshot.Aliases
		ConfigurationKeys = $Snapshot.ConfigurationKeys
		Deprecated        = $deprecated
	}
}

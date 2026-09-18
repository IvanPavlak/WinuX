function Test-MachineTypeScope {
	<#
	.SYNOPSIS
		Tests whether a machine-scope string ("All", "PC/Laptop", ...) applies to a machine type, validating every token.

	.DESCRIPTION
		The single gate behind every machine-scoped data source: the Machine column of the
		WinGet/Scoop/Chocolatey CSVs and the BootstrapConfig.PersonalSteps entries. Splits the
		scope string on "/", trims each token, and returns $true when the scope names "All" or
		the given machine type (matching is case-insensitive, so "laptop" covers "Laptop").

		Every token is checked against ValidMachineTypes from the configuration plus the "All"
		wildcard. Unknown tokens (e.g. the typo "Labtop") are reported through Write-LogError
		together with the valid values, and contribute nothing to the match - so a misspelled
		scope can never silently install or skip anything. A blank scope is reported the same
		way and never matches. When neither the configuration nor -AdditionalValidTypes names
		any type (synthetic test configurations), token validation is skipped and only matching
		is performed.

		-AdditionalValidTypes widens the accepted token set for scopes that name something other
		than a machine type. Resolve-WorkspaceActions uses it for the LayoutMachine key of
		WorkspaceActions entries, whose tokens are LAYOUT SETS: the values of
		LayoutMachineTypeOverrides and SmallDisplayMachineType (e.g. "Temp") are valid there even
		though they are not machine types.

	.PARAMETER Scope
		The machine-scope string: one or more machine types separated by "/" (e.g. "PC/Laptop"),
		or "All" to cover every machine type.

	.PARAMETER MachineType
		Machine type to test the scope against. Defaults to $global:MachineType (resolved by
		Load-PathConfiguration / DetermineMachineType). When empty, only "All" scopes match.

	.PARAMETER Context
		Optional label naming the data source (e.g. "WinGetApps.csv [Git.Git]"), included in
		error messages so an invalid token can be located and fixed immediately.

	.PARAMETER AdditionalValidTypes
		Extra tokens accepted alongside ValidMachineTypes (blanks ignored, duplicates collapsed).
		Supplying them turns token validation on even when the configuration defines no
		ValidMachineTypes, since there is then something to validate against.

	.EXAMPLE
		Test-MachineTypeScope -Scope "PC/Laptop" -MachineType "Laptop"
		Returns $true - the scope covers Laptop.

	.EXAMPLE
		Test-MachineTypeScope -Scope "Labtop" -MachineType "Laptop" -Context "WinGetApps.csv [MyApp]"
		Returns $false and reports the unknown token [Labtop] with the list of valid values.

	.EXAMPLE
		Test-MachineTypeScope -Scope "Temp" -MachineType "Temp" -AdditionalValidTypes "Temp"
		Returns $true - "Temp" is a layout set, not a machine type, and is accepted only because it was
		passed in explicitly.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $false)]
		[AllowEmptyString()]
		[string]$Scope,

		[Parameter(Mandatory = $false)]
		[string]$MachineType = $global:MachineType,

		[Parameter(Mandatory = $false)]
		[string]$Context,

		[Parameter(Mandatory = $false)]
		[AllowEmptyCollection()]
		[string[]]$AdditionalValidTypes
	)

	$contextSuffix = if ($Context) { " in [$Context]" } else { "" }
	$validTypes = @(
		@(@(Get-ConfigSetting -Path 'ValidMachineTypes' -Default @()) + @($AdditionalValidTypes)) |
			ForEach-Object { if ($null -ne $_) { ([string]$_).Trim() } } |
			Where-Object { $_ } |
			Select-Object -Unique
	)

	$tokens = @(("$Scope").Trim() -split "/" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
	if ($tokens.Count -eq 0) {
		Write-LogError "Empty machine scope$contextSuffix - expected 'All' or machine types separated by '/'"
		return $false
	}

	# Validate every token against the configured machine types (plus the "All" wildcard) so a
	# typo like "Labtop" is reported instead of silently never matching. Configurations without
	# ValidMachineTypes (synthetic test configs) skip validation and keep pure matching behavior.
	$recognizedTokens = @(foreach ($token in $tokens) {
			if ($token -eq "All" -or $validTypes.Count -eq 0 -or $token -in $validTypes) {
				$token
			}
			else {
				Write-LogError "Unknown machine type [$token]$contextSuffix - valid values: $(@(@("All") + $validTypes) -join ', ')"
			}
		})

	return ("All" -in $recognizedTokens -or ($MachineType -and $MachineType -in $recognizedTokens))
}

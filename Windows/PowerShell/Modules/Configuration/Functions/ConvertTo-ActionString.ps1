function ConvertTo-ActionString {
	<#
	.SYNOPSIS
		Converts an action hashtable to a Configuration.psd1 entry string.
	.DESCRIPTION
		Formats an action hashtable as a properly formatted string for
		insertion into WorkspaceActions or ProjectActions sections. Hashtable
		values (Parameters, and the per-machine tables MachineParameters /
		LayoutMachineParameters - see Resolve-WorkspaceActions) are written
		recursively with their keys in alphabetical order, so the output is
		stable; a key that is not a plain identifier (a machine scope such as
		"Laptop/Work") is quoted. The machine scopes (Machine, LayoutMachine)
		are written last, so Add-Workspace keeps every machine key intact.
	.PARAMETER Action
		The action hashtable with Action, optional Parameters, optional
		MachineParameters / LayoutMachineParameters tables and optional
		Machine / LayoutMachine scope keys.
	.PARAMETER Indent
		The indentation prefix for the output string.
	.EXAMPLE
		ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } } -Indent "`t`t`t"
	.EXAMPLE
		ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } } -Indent "`t`t`t"
		# @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = "2" } } }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[hashtable]$Action,

		[Parameter(Mandatory)]
		[string]$Indent
	)

	# A key is written bare when it is a plain identifier, quoted otherwise ("Laptop/Work").
	$formatKey = {
		param([string]$Key)
		if ($Key -match '^[A-Za-z_]\w*$') { return $Key }
		return "`"$Key`""
	}

	# Values: $null, booleans, nested hashtables (sorted keys), arrays of quoted items, and
	# everything else as a quoted string.
	$formatValue = {
		param($Value)
		if ($null -eq $Value) { return '$null' }
		if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
		if ($Value -is [System.Collections.IDictionary]) {
			$keys = @($Value.Keys | ForEach-Object { [string]$_ })
			if ($keys.Count -eq 0) { return '@{}' }
			if ($keys.Count -gt 1) { [Array]::Sort($keys, [System.StringComparer]::Ordinal) }
			$parts = @(foreach ($key in $keys) { "$(& $formatKey $key) = $(& $formatValue $Value[$key])" })
			return "@{ $($parts -join '; ') }"
		}
		if ($Value -is [array]) {
			$quoted = ($Value | ForEach-Object { "`"$_`"" }) -join ", "
			return "@($quoted)"
		}
		return "`"$Value`""
	}

	$str = "$Indent@{ Action = `"$($Action.Action)`""

	if ($Action.Parameters -and $Action.Parameters.Count -gt 0) {
		$str += "; Parameters = $(& $formatValue $Action.Parameters)"
	}

	# The per-machine parameter tables are parameter-shaped, so they follow Parameters.
	foreach ($tableKey in @('MachineParameters', 'LayoutMachineParameters')) {
		if ($Action.ContainsKey($tableKey)) {
			$table = $Action[$tableKey]
			if ($table -is [System.Collections.IDictionary] -and $table.Count -gt 0) {
				$str += "; $tableKey = $(& $formatValue $table)"
			}
		}
	}

	# Machine scopes last, the way the TaskbarConfiguration rows carry theirs.
	foreach ($scopeKey in @('Machine', 'LayoutMachine')) {
		if ($Action.ContainsKey($scopeKey)) {
			$scope = $Action[$scopeKey]
			if ($scope -is [array]) { $scope = (@($scope) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join '/' }
			if (-not [string]::IsNullOrWhiteSpace([string]$scope)) {
				$str += "; $scopeKey = `"$(([string]$scope).Trim())`""
			}
		}
	}

	$str += " }"
	return $str
}

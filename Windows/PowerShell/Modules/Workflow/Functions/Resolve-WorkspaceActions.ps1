function Resolve-WorkspaceActions {
	<#
	.SYNOPSIS
		Resolves a workspace's configured actions for this machine: which ones run, and with which parameters.

	.DESCRIPTION
		A WorkspaceActions entry may carry four optional machine keys next to Action and Parameters.
		Two SCOPE keys decide whether the action runs at all, two TABLE keys vary its parameters:

		  Machine                 - the machine TYPES the action runs on, matched against the detected
		                            machine type ($global:MachineType, from DetermineMachineType).
		                            Identity-shaped: an Open-Outlook that only belongs on the Work machine.
		  LayoutMachine           - the LAYOUT SETS the action runs on, matched against the machine type
		                            Get-LayoutMachineType resolves for window arrangement (a non-empty
		                            LayoutMachineTypeOverrides entry, else SmallDisplayMachineType on a
		                            small display, else the detected type) - the same set
		                            Set-WorkspaceWindowLayout reads the layout file from.
		  MachineParameters       - @{ "<scope>" = @{ <parameter overrides> } }, rows matched against the
		                            detected machine type; the matching rows are merged over Parameters.
		  LayoutMachineParameters - the same, rows matched against the layout set. Display-shaped: an
		                            "Open-Browser" whose window count has to agree with the layout that
		                            will be applied carries Parameters = @{ Groups = @("Google") } for
		                            every machine and LayoutMachineParameters = @{ PC = @{ Instances = 2 } }
		                            for the two-zone PC layout - one entry instead of one per layout set.
		                            When the PC is redirected to the Work layouts the PC row does not
		                            apply, so the open produces exactly the windows
		                            LeagueOfLegends_Work.psd1 expects.

		Scopes and row keys take the machine-scope string Test-MachineTypeScope understands, exactly
		like the TaskbarConfiguration rows and the app CSVs' Machine column: "All", one type, or several
		separated by "/" ("Laptop/Work"). An array of tokens is accepted for the scope keys. An absent
		or blank scope key means "All". An action runs only when both scopes match. Skipped actions are
		reported at debug level, and a token that is not a known type is reported through
		Write-LogError with the workspace and action named, so a typo can never silently skip (or
		keep) an action or a row.

		Machine tokens are validated against ValidMachineTypes. LayoutMachine tokens are validated
		against ValidMachineTypes plus every non-empty LayoutMachineTypeOverrides value and
		SmallDisplayMachineType, because a layout set such as "Temp" is not a machine type and has no
		ValidMachineTypes entry (see Get-LayoutMachineType). The same two rules apply to the row keys of
		MachineParameters and LayoutMachineParameters respectively.

		Parameter tables are the MachineOverrides idea applied to one action: Parameters is the
		default, a row is the difference. Every row whose key covers this machine is deep-merged over
		a COPY of Parameters (nested hashtables merge key by key, everything else is replaced), the
		"All" row first, then the remaining matching rows in alphabetical key order (a psd1 hashtable
		keeps no order), MachineParameters before LayoutMachineParameters - the layout set is the
		derived, more specific statement about the machine as it is running right now, so a
		display-shaped value wins over an identity-shaped one. A parameter set to $null by a row is
		REMOVED, so a machine can drop a parameter as well as change it (an explicit $null would
		otherwise be bound by the action, and a present key keeps Open-Workspace from filling in a
		command-line value). Only top-level parameters are removed this way; a $null inside a nested
		hashtable is the action's own business. The configuration object is never modified: an entry
		with a table comes back as a new hashtable carrying the merged Parameters and every other key
		except the two tables, an entry without tables comes back as the very same object.

		The layout set is resolved lazily: Get-LayoutMachineType is called at most once, and only when
		some action actually carries LayoutMachine or LayoutMachineParameters and -LayoutMachineType was
		not supplied - a workspace without those keys costs nothing beyond the machine-type lookup.
		Without the Window module the layout set falls back to the detected machine type.

		Entries are returned in their original order, so Open-Workspace runs the resolved list exactly
		as it would have run the configured one. When a non-empty list resolves to nothing, a warning
		names the machine type (and layout set) that excluded every action; the callers then skip the
		workspace instead of recording an open that produced nothing.

	.PARAMETER Actions
		The configured action entries of one workspace (the value of $Configuration.WorkspaceActions
		for that workspace): hashtables (or objects) with Action, optional Parameters, and the optional
		Machine / LayoutMachine scopes and MachineParameters / LayoutMachineParameters tables. Null or
		empty resolves to an empty array.

	.PARAMETER Workspace
		The workspace name, used in the debug, warning and unknown-token messages.

	.PARAMETER MachineType
		The detected machine type the Machine scopes and MachineParameters rows are matched against.
		Defaults to $global:MachineType (set by Load-PathConfiguration / DetermineMachineType).

	.PARAMETER LayoutMachineType
		The layout set the LayoutMachine scopes and LayoutMachineParameters rows are matched against.
		Omit it to have it resolved through Get-LayoutMachineType when needed; pass it when the caller
		already resolved it.

	.PARAMETER Configuration
		The configuration hashtable the layout-set tokens (LayoutMachineTypeOverrides,
		SmallDisplayMachineType) are read from. Defaults to $global:Configuration;
		Measure-WorkspaceOpen hands over the configuration it was given.

	.OUTPUTS
		[object[]] The entries that apply, in configured order, with their parameters resolved.

	.EXAMPLE
		$actions = Resolve-WorkspaceActions -Actions $Configuration.WorkspaceActions['LeagueOfLegends'] -Workspace 'LeagueOfLegends'
		# The entry @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
		# comes back with Instances = 2 on the PC's own layout set and without Instances on Laptop, Work,
		# and on the PC while it is redirected to the Work layouts.

	.EXAMPLE
		Resolve-WorkspaceActions -Actions $actions -Workspace 'Server' -MachineType 'Laptop' -LayoutMachineType 'Laptop'
		# Resolves for an explicit machine type and layout set without touching the live machine.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter(Position = 0)]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Actions,

		[Parameter()]
		[string]$Workspace,

		[Parameter()]
		[string]$MachineType = $global:MachineType,

		[Parameter()]
		[string]$LayoutMachineType,

		[Parameter()]
		[AllowNull()]
		[hashtable]$Configuration = $global:Configuration
	)

	$tableKeys = @('MachineParameters', 'LayoutMachineParameters')

	# Whether an entry (hashtable from the psd1, or an object) carries a key at all.
	$hasEntryKey = {
		param($Entry, [string]$Key)
		if ($Entry -is [System.Collections.IDictionary]) { return $Entry.Contains($Key) }
		return ($null -ne $Entry -and $null -ne $Entry.PSObject.Properties[$Key])
	}

	# Reads one key as-is (Parameters and the tables need the real value, not a string).
	$readEntryRaw = {
		param($Entry, [string]$Key)
		if ($Entry -is [System.Collections.IDictionary]) {
			if ($Entry.Contains($Key)) { return $Entry[$Key] }
			return $null
		}
		if ($null -ne $Entry -and $Entry.PSObject.Properties[$Key]) { return $Entry.PSObject.Properties[$Key].Value }
		return $null
	}

	# Reads one key as the "A/B" scope string Test-MachineTypeScope takes. Blank => "" (All).
	$readEntryValue = {
		param($Entry, [string]$Key)
		$value = & $readEntryRaw $Entry $Key
		if ($value -is [array]) {
			$value = (@($value) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join '/'
		}
		if ($null -eq $value) { return '' }
		return ([string]$value).Trim()
	}

	# Deep copy: dictionaries become plain hashtables (so nested merges recurse reliably), arrays
	# become new arrays, everything else is a value. Nothing returned aliases the configuration.
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

	# Merge-Hashtable's rule (hashtables merge key by key, everything else replaces) applied to a
	# working copy with copied override values, so a later row can never reach into the psd1's own
	# nested hashtables. Kept private: the Workflow module does not depend on Bootstrap.
	$mergeInto = {
		param([hashtable]$Target, $Overrides)
		foreach ($key in $Overrides.Keys) {
			if ($Target.ContainsKey($key) -and $Target[$key] -is [System.Collections.IDictionary] -and $Overrides[$key] -is [System.Collections.IDictionary]) {
				& $mergeInto $Target[$key] $Overrides[$key]
			}
			else {
				$Target[$key] = & $copyDeep $Overrides[$key]
			}
		}
	}

	$entries = @($Actions | Where-Object { $null -ne $_ })
	if ($entries.Count -eq 0) {
		return @()
	}

	$workspaceLabel = if ([string]::IsNullOrWhiteSpace($Workspace)) { '' } else { ".$Workspace" }

	# The layout set is only worth resolving (Get-LayoutMachineType may query the monitors) when an
	# entry actually asks for it - through the LayoutMachine scope or a LayoutMachineParameters table.
	$needsLayoutSet = $false
	foreach ($entry in $entries) {
		if (-not [string]::IsNullOrWhiteSpace((& $readEntryValue $entry 'LayoutMachine'))) { $needsLayoutSet = $true; break }
		if (& $hasEntryKey $entry 'LayoutMachineParameters') { $needsLayoutSet = $true; break }
	}

	$layoutSet = $LayoutMachineType
	if ($needsLayoutSet -and [string]::IsNullOrWhiteSpace($layoutSet)) {
		if (Get-Command Get-LayoutMachineType -ErrorAction SilentlyContinue) {
			try {
				$layoutSet = [string](Get-LayoutMachineType)
			}
			catch {
				Write-LogDebug " [Resolve-WorkspaceActions] Get-LayoutMachineType failed => $($_.Exception.Message) - using machine type [$MachineType] as the layout set" -Style Warning
				$layoutSet = $MachineType
			}
		}
		else {
			$layoutSet = $MachineType
		}
		if ([string]::IsNullOrWhiteSpace($layoutSet)) { $layoutSet = $MachineType }
	}

	# Layout sets that are not machine types but are valid LayoutMachine tokens: every non-empty
	# LayoutMachineTypeOverrides value and SmallDisplayMachineType (single-element arrays unwrapped
	# the way Get-LayoutMachineType reads them).
	$layoutSetTokens = @()
	if ($null -ne $Configuration) {
		$overrides = $Configuration['LayoutMachineTypeOverrides']
		if ($overrides -is [System.Collections.IDictionary]) {
			foreach ($overrideValue in @($overrides.Values)) {
				$candidate = $overrideValue
				if ($candidate -is [array]) { $candidate = @($candidate)[0] }
				if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $layoutSetTokens += ([string]$candidate).Trim() }
			}
		}
		$smallDisplayType = $Configuration['SmallDisplayMachineType']
		if ($smallDisplayType -is [array]) { $smallDisplayType = @($smallDisplayType)[0] }
		if (-not [string]::IsNullOrWhiteSpace([string]$smallDisplayType)) { $layoutSetTokens += ([string]$smallDisplayType).Trim() }
	}
	$layoutSetTokens = @($layoutSetTokens | Select-Object -Unique)

	# Applies one parameter table to the working copy: "All" row first, then the other matching rows
	# in alphabetical order. Rows with an unknown key or a non-hashtable value are reported and skipped.
	$applyTable = {
		param($Entry, [string]$TableName, [string]$AxisValue, [string[]]$ExtraTokens, [hashtable]$Working, [string]$ActionName)
		$table = & $readEntryRaw $Entry $TableName
		if ($null -eq $table) { return }

		$context = "WorkspaceActions$workspaceLabel [$ActionName].$TableName"
		if (-not ($table -is [System.Collections.IDictionary])) {
			Write-LogError "$context must be a hashtable of machine scope => parameter overrides (got [$($table.GetType().Name)]) - ignored"
			return
		}

		$keys = @($table.Keys | ForEach-Object { [string]$_ })
		$allRows = @($keys | Where-Object { $_.Trim() -eq 'All' })
		$otherRows = @($keys | Where-Object { $_.Trim() -ne 'All' })
		if ($otherRows.Count -gt 1) { [Array]::Sort($otherRows, [System.StringComparer]::OrdinalIgnoreCase) }

		$applied = @()
		foreach ($rowKey in @($allRows + $otherRows)) {
			$scopeSplat = @{ Scope = $rowKey; MachineType = $AxisValue; Context = $context }
			if ($ExtraTokens.Count -gt 0) { $scopeSplat['AdditionalValidTypes'] = $ExtraTokens }
			if (-not (Test-MachineTypeScope @scopeSplat)) { continue }

			$row = $table[$rowKey]
			if (-not ($row -is [System.Collections.IDictionary])) {
				$rowType = if ($null -eq $row) { 'null' } else { $row.GetType().Name }
				Write-LogError "$context row [$rowKey] must be a hashtable of parameter overrides (got [$rowType]) - ignored"
				continue
			}

			& $mergeInto $Working $row
			$applied += $rowKey
			Write-LogDebug " [Resolve-WorkspaceActions] [$ActionName] for [$Workspace] - $TableName [$rowKey] applied on [$AxisValue] => $(@($row.Keys) -join ', ')" -Style Success
		}

		if ($applied.Count -gt 1) {
			Write-LogDebug " [Resolve-WorkspaceActions] [$ActionName] for [$Workspace] - $TableName rows applied in order => [$($applied -join '], [')]" -Style Warning
		}
	}

	# Rebuilds an entry with the resolved parameters and without the tables; Action, the scopes and
	# any other key are carried over.
	$rebuildEntry = {
		param($Entry, [hashtable]$Parameters)
		$rebuilt = @{}
		if ($Entry -is [System.Collections.IDictionary]) {
			foreach ($key in $Entry.Keys) {
				if ([string]$key -in $tableKeys) { continue }
				$rebuilt[$key] = $Entry[$key]
			}
		}
		else {
			foreach ($property in $Entry.PSObject.Properties) {
				if ($property.Name -in $tableKeys) { continue }
				$rebuilt[$property.Name] = $property.Value
			}
		}
		$rebuilt['Parameters'] = $Parameters
		return $rebuilt
	}

	# Collected explicitly rather than captured from the loop's output, so nothing a logging call
	# might emit can ever be mistaken for an action.
	$resolved = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in $entries) {
		$actionName = & $readEntryValue $entry 'Action'
		$context = "WorkspaceActions$workspaceLabel [$actionName]"

		$machineScope = & $readEntryValue $entry 'Machine'
		if (-not [string]::IsNullOrWhiteSpace($machineScope)) {
			if (-not (Test-MachineTypeScope -Scope $machineScope -MachineType $MachineType -Context $context)) {
				Write-LogDebug " [Resolve-WorkspaceActions] Skipping [$actionName] for [$Workspace] - Machine [$machineScope] does not cover machine type [$MachineType]" -Style Warning
				continue
			}
		}

		$layoutScope = & $readEntryValue $entry 'LayoutMachine'
		if (-not [string]::IsNullOrWhiteSpace($layoutScope)) {
			if (-not (Test-MachineTypeScope -Scope $layoutScope -MachineType $layoutSet -Context $context -AdditionalValidTypes $layoutSetTokens)) {
				Write-LogDebug " [Resolve-WorkspaceActions] Skipping [$actionName] for [$Workspace] - LayoutMachine [$layoutScope] does not cover layout set [$layoutSet]" -Style Warning
				continue
			}
		}

		# The scope check runs first, so an action that does not run here never reports table errors.
		$hasMachineTable = & $hasEntryKey $entry 'MachineParameters'
		$hasLayoutTable = & $hasEntryKey $entry 'LayoutMachineParameters'
		if (-not ($hasMachineTable -or $hasLayoutTable)) {
			$resolved.Add($entry)
			continue
		}

		$baseParameters = & $readEntryRaw $entry 'Parameters'
		$working = if ($baseParameters -is [System.Collections.IDictionary]) { & $copyDeep $baseParameters } else { @{} }

		if ($hasMachineTable) { & $applyTable $entry 'MachineParameters' $MachineType @() $working $actionName }
		if ($hasLayoutTable) { & $applyTable $entry 'LayoutMachineParameters' $layoutSet $layoutSetTokens $working $actionName }

		# $null from a row means "not on this machine": drop the parameter instead of binding $null.
		foreach ($key in @($working.Keys)) {
			if ($null -eq $working[$key]) { $working.Remove($key) }
		}

		$resolved.Add((& $rebuildEntry $entry $working))
	}

	if ($resolved.Count -eq 0) {
		$layoutSuffix = if ($needsLayoutSet) { " (layout set [$layoutSet])" } else { '' }
		Write-LogWarning "No actions of workspace [$Workspace] apply on machine type [$MachineType]$layoutSuffix - every action is scoped to another machine"
	}

	return $resolved.ToArray()
}

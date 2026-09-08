function Resolve-WorkspaceActions {
	<#
	.SYNOPSIS
		Filters a workspace's configured actions down to the ones that apply on this machine and its layout set.

	.DESCRIPTION
		A WorkspaceActions entry may carry two optional scope keys next to Action and Parameters:

		  Machine       - the machine TYPES the action runs on, matched against the detected machine
		                  type ($global:MachineType, from DetermineMachineType). Identity-shaped: an
		                  Open-Outlook that only belongs on the Work machine.
		  LayoutMachine - the LAYOUT SETS the action runs on, matched against the machine type
		                  Get-LayoutMachineType resolves for window arrangement (a non-empty
		                  LayoutMachineTypeOverrides entry, else SmallDisplayMachineType on a small
		                  display, else the detected type) - the same set Set-WorkspaceWindowLayout
		                  reads the layout file from. Display-shaped: an "Open-Browser -Instances 2"
		                  whose window count has to agree with the layout that will be applied. When
		                  the PC is redirected to the Work layouts, its LayoutMachine = "Work" actions
		                  run and its LayoutMachine = "PC" actions do not, so the open produces exactly
		                  the windows LeagueOfLegends_Work.psd1 expects.

		Both keys take the machine-scope string Test-MachineTypeScope understands, exactly like the
		TaskbarConfiguration rows and the app CSVs' Machine column: "All", one type, or several
		separated by "/" ("Laptop/Work"). An array of tokens is accepted too. An absent or blank key
		means "All". An action runs only when both scopes match. Skipped actions are reported at debug
		level, and a token that is not a known type is reported through Write-LogError with the
		workspace and action named, so a typo can never silently skip (or keep) an action.

		Machine tokens are validated against ValidMachineTypes. LayoutMachine tokens are validated
		against ValidMachineTypes plus every non-empty LayoutMachineTypeOverrides value and
		SmallDisplayMachineType, because a layout set such as "Temp" is not a machine type and has no
		ValidMachineTypes entry (see Get-LayoutMachineType).

		The layout set is resolved lazily: Get-LayoutMachineType is called at most once, and only when
		some action actually carries LayoutMachine and -LayoutMachineType was not supplied - a workspace
		without the key costs nothing beyond the machine-type lookup. Without the Window module the
		layout set falls back to the detected machine type.

		Entries are returned unchanged and in their original order, so Open-Workspace runs the resolved
		list exactly as it would have run the configured one. When a non-empty list resolves to nothing,
		a warning names the machine type (and layout set) that excluded every action; the callers then
		skip the workspace instead of recording an open that produced nothing.

	.PARAMETER Actions
		The configured action entries of one workspace (the value of $Configuration.WorkspaceActions
		for that workspace): hashtables (or objects) with Action, optional Parameters, and the optional
		Machine / LayoutMachine scopes. Null or empty resolves to an empty array.

	.PARAMETER Workspace
		The workspace name, used in the debug, warning and unknown-token messages.

	.PARAMETER MachineType
		The detected machine type the Machine scopes are matched against. Defaults to
		$global:MachineType (set by Load-PathConfiguration / DetermineMachineType).

	.PARAMETER LayoutMachineType
		The layout set the LayoutMachine scopes are matched against. Omit it to have it resolved through
		Get-LayoutMachineType when needed; pass it when the caller already resolved it.

	.PARAMETER Configuration
		The configuration hashtable the layout-set tokens (LayoutMachineTypeOverrides,
		SmallDisplayMachineType) are read from. Defaults to $global:Configuration;
		Measure-WorkspaceOpen hands over the configuration it was given.

	.OUTPUTS
		[object[]] The entries that apply, in configured order.

	.EXAMPLE
		$actions = Resolve-WorkspaceActions -Actions $Configuration.WorkspaceActions['LeagueOfLegends'] -Workspace 'LeagueOfLegends'
		# On a machine whose layout set is Work: the Open-Browser entry scoped LayoutMachine = "Laptop/Work"
		# is kept, the one scoped LayoutMachine = "PC" is skipped, every unscoped entry is kept.

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

	# Reads one key off an entry whether it is a hashtable (psd1) or an object, and normalizes the
	# scope to the "A/B" string Test-MachineTypeScope takes. Blank => "" (treated as All below).
	$readEntryValue = {
		param($Entry, [string]$Key)
		$value = $null
		if ($Entry -is [System.Collections.IDictionary]) {
			if ($Entry.Contains($Key)) { $value = $Entry[$Key] }
		}
		elseif ($null -ne $Entry -and $Entry.PSObject.Properties[$Key]) {
			$value = $Entry.PSObject.Properties[$Key].Value
		}
		if ($value -is [array]) {
			$value = (@($value) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join '/'
		}
		if ($null -eq $value) { return '' }
		return ([string]$value).Trim()
	}

	$entries = @($Actions | Where-Object { $null -ne $_ })
	if ($entries.Count -eq 0) {
		return @()
	}

	$workspaceLabel = if ([string]::IsNullOrWhiteSpace($Workspace)) { '' } else { ".$Workspace" }

	# The layout set is only worth resolving (Get-LayoutMachineType may query the monitors) when an
	# entry actually asks for it.
	$needsLayoutSet = $false
	foreach ($entry in $entries) {
		if (-not [string]::IsNullOrWhiteSpace((& $readEntryValue $entry 'LayoutMachine'))) { $needsLayoutSet = $true; break }
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

		$resolved.Add($entry)
	}

	if ($resolved.Count -eq 0) {
		$layoutSuffix = if ($needsLayoutSet) { " (layout set [$layoutSet])" } else { '' }
		Write-LogWarning "No actions of workspace [$Workspace] apply on machine type [$MachineType]$layoutSuffix - every action is scoped to another machine"
	}

	return $resolved.ToArray()
}

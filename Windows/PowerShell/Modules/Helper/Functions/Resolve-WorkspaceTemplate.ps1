function Resolve-WorkspaceTemplate {
	<#
	.SYNOPSIS
		Expands one WorkspaceActions entry into the ordinary action list Open-Workspace runs.

	.DESCRIPTION
		A WorkspaceActions entry has one of two shapes:

		  Plain     @{ Name = @( <action entries> ) }
		  Templated @{ Name = @{ Template = "<template>"; Variables = @{ ... }; Overrides = @{ ... }; Add = @( ... ) } }

		A templated entry stamps out the action list of a WorkspaceTemplates entry
		(@{ Variables = @{ <name> = <default> }; Actions = @( <action entries> ) }) under its own
		name, so everything keyed by the workspace name (layout file, open/close tracker, alongside
		protection, benchmarks, the Obsidian workspace, DefaultVSCodeWorkspaces) keeps working
		per workspace. The expansion runs in this order:

		  1. The template's actions are copied. A template action may carry an optional Id next to
		     the ordinary keys, as a stable name for Overrides and Add anchors.
		  2. Overrides, keyed by Id first and then by action name, are merged over their target:
		     the value is entry-shaped (Parameters, Machine, LayoutMachine, MachineParameters,
		     LayoutMachineParameters, Project, ProjectParameters). Nested hashtables merge key by
		     key, lists replace, a top-level parameter set to $null is removed, a key set to $null
		     is removed, and an override value of $null drops the action. An action name that
		     matches several template actions is an error - give them an Id.
		  3. Add inserts ordinary action entries, by default just before the template's first
		     Set-WorkspaceWindowLayout (the end of the list when there is none). Before = "<Id or
		     action>" or After = "<Id or action>" places one explicitly.
		  4. Variables are substituted in every value of every action. A value that is exactly
		     "{Name}" receives the variable's value as it is (a list, a hashtable, $true), the way
		     {SelectedProjects} behaves; inside a longer string "{Name}" is replaced by the text of
		     a scalar value. {Workspace} is built in and holds the entry's own name. Defaults may
		     reference {Workspace} and other variables; a cycle is an error.

		Variable values come from the template's Variables, overlaid by the entry's Variables,
		overlaid by -Variables (the command line). -Variables only sets names the template or the
		entry declares; every other key is ignored, so a caller can hand over all of its extra
		arguments and forward the rest to the actions (see AppliedVariables).

		Reserved names cannot be variables: Workspace, SelectedProjects, ProjectName, Dev, User,
		MachineType, RepoRoot, AppData. The engine tokens among them are left untouched for the
		code that resolves them later. Inside a templated entry any other {Name} that is not a
		declared variable is an error, so a typo can never reach an action as literal text. A
		variable used without a value (declared with $null and never set) is an error too.

		A plain entry only gets {Workspace} substituted; it comes back with the very same action
		objects (Changed = $false) when it does not use the token, and any other brace text in it is left alone.

		Errors are returned, never thrown or logged: the caller decides whether a broken entry is
		reported at load (Expand-WorkspaceTemplates), when it is opened (Open-Workspace) or by
		Test-ConfigurationSchema. An entry with errors resolves to no actions.

	.PARAMETER Name
		The workspace name - the WorkspaceActions key. It is the value of {Workspace}.

	.PARAMETER Definition
		The entry's value: a templated definition (hashtable) or a plain action list.

	.PARAMETER Templates
		The WorkspaceTemplates section. Defaults to $global:Configuration.WorkspaceTemplates.

	.PARAMETER Variables
		Variable values that win over the template's and the entry's (the command line). Keys the
		template and the entry do not declare are ignored.

	.OUTPUTS
		[pscustomobject] with
		  Name             - the workspace name
		  IsTemplated      - $true for a templated definition
		  Template         - the template name ('' for a plain entry)
		  Actions          - [object[]] the expanded action list (empty when Errors is not)
		  Changed          - $false when a plain list came back untouched
		  VariableNames    - [string[]] the variables the template and the entry declare
		  AppliedVariables - [string[]] the -Variables keys that were used
		  Errors           - [string[]] one message per problem, naming the workspace

	.EXAMPLE
		$templates = @{ Project = @{ Variables = @{ Repository = "{Workspace}Repository" }; Actions = @(
				@{ Action = "Open-Project"; Parameters = @{ Project = "{Workspace}" } }
				@{ Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}", "AI") } }
			) } }
		(Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project' } -Templates $templates).Actions
		# Open-Project -Project MyProject, then Open-Browser -Groups MyProjectRepository, AI

	.EXAMPLE
		Resolve-WorkspaceTemplate -Name 'MyRepo' -Definition @{ Template = 'Project' } -Templates $templates -Variables @{ Repository = 'OtherGroup'; Instances = 2 }
		# Repository is used (AppliedVariables = Repository), Instances is not a variable and is ignored.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory = $true, Position = 1)]
		[AllowNull()]
		[object]$Definition,

		[Parameter()]
		[AllowNull()]
		[object]$Templates = $(if ($global:Configuration -is [System.Collections.IDictionary]) { $global:Configuration['WorkspaceTemplates'] }),

		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$Variables
	)

	$reservedNames = @('Workspace', 'SelectedProjects', 'ProjectName', 'Dev', 'User', 'MachineType', 'RepoRoot', 'AppData')
	$entryKeys = @('Template', 'Variables', 'Overrides', 'Add')
	$templateKeys = @('Variables', 'Actions')
	$overrideKeys = @('Parameters', 'Machine', 'LayoutMachine', 'MachineParameters', 'LayoutMachineParameters', 'Project', 'ProjectParameters')
	$tableKeys = @('MachineParameters', 'LayoutMachineParameters', 'ProjectParameters')
	$tokenPattern = '\{([A-Za-z][A-Za-z0-9_]*)\}'

	$state = @{
		Errors    = [System.Collections.Generic.List[string]]::new()
		Strict    = $false
		Resolved  = @{}
		Resolving = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		Variables = @{}
	}
	$addError = { param([string]$Message) $state.Errors.Add("WorkspaceActions.$Name - $Message") }

	# Deep copy: dictionaries become plain hashtables, lists become new arrays, everything else is
	# a value. Nothing returned aliases the configuration.
	$copyDeep = {
		param($Value)
		if ($Value -is [System.Collections.IDictionary]) {
			$copy = @{}
			foreach ($key in $Value.Keys) { $copy[$key] = & $copyDeep $Value[$key] }
			return $copy
		}
		if ($Value -is [System.Collections.IList]) {
			$items = @(foreach ($item in $Value) { , (& $copyDeep $item) })
			return , $items
		}
		return $Value
	}

	# Hashtables merge key by key, everything else is replaced by a copy (a $null included).
	$mergeDeep = {
		param([hashtable]$Target, [System.Collections.IDictionary]$Overrides)
		foreach ($key in $Overrides.Keys) {
			if ($Target.ContainsKey($key) -and $Target[$key] -is [System.Collections.IDictionary] -and $Overrides[$key] -is [System.Collections.IDictionary]) {
				if (-not ($Target[$key] -is [hashtable])) { $Target[$key] = & $copyDeep $Target[$key] }
				& $mergeDeep $Target[$key] $Overrides[$key]
			}
			else {
				$Target[$key] = & $copyDeep $Overrides[$key]
			}
		}
	}

	# Whether any string inside a value carries the {Workspace} token (plain entries only).
	$containsWorkspaceToken = {
		param($Value)
		if ($Value -is [string]) { return $Value.IndexOf('{Workspace}', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
		if ($Value -is [System.Collections.IDictionary]) {
			foreach ($key in $Value.Keys) { if (& $containsWorkspaceToken $Value[$key]) { return $true } }
			return $false
		}
		if ($Value -is [System.Collections.IList]) {
			foreach ($item in $Value) { if (& $containsWorkspaceToken $item) { return $true } }
		}
		return $false
	}

	# What a {Name} token stands for: Value (with .Value), Engine (left for later code), Unknown,
	# or Error (already reported). Variables resolve lazily, so a default that references another
	# variable is substituted first and a cycle is caught on the way.
	$lookup = {
		param([string]$TokenName)
		if ($TokenName -ieq 'Workspace') { return @{ Kind = 'Value'; Value = $Name } }
		if ($state.Variables.ContainsKey($TokenName)) {
			if ($state.Resolved.ContainsKey($TokenName)) { return @{ Kind = 'Value'; Value = $state.Resolved[$TokenName] } }
			if ($state.Resolving.Contains($TokenName)) {
				& $addError "variable [$TokenName] references itself (cycle through $(@($state.Resolving) -join ' -> '))"
				return @{ Kind = 'Error' }
			}
			$rawValue = $state.Variables[$TokenName]
			if ($null -eq $rawValue) {
				& $addError "variable [$TokenName] is used but has no value - set it in the entry's Variables or on the command line"
				return @{ Kind = 'Error' }
			}
			[void]$state.Resolving.Add($TokenName)
			$resolvedValue = & $substitute $rawValue "variable [$TokenName]"
			[void]$state.Resolving.Remove($TokenName)
			$state.Resolved[$TokenName] = $resolvedValue
			return @{ Kind = 'Value'; Value = $resolvedValue }
		}
		if ($reservedNames -contains $TokenName) { return @{ Kind = 'Engine' } }
		return @{ Kind = 'Unknown' }
	}

	# Substitutes every {Name} token inside a value and returns a copy.
	$substitute = {
		param($Value, [string]$Where)
		if ($Value -is [string]) {
			# Most values carry no placeholder at all; skip the regex work for them.
			if ($Value.IndexOf('{') -lt 0) { return $Value }
			$wholeMatch = [regex]::Match($Value, "^$tokenPattern$")
			if ($wholeMatch.Success) {
				$tokenName = $wholeMatch.Groups[1].Value
				$found = & $lookup $tokenName
				switch ($found.Kind) {
					'Value' { return , (& $copyDeep $found.Value) }
					'Unknown' {
						if ($state.Strict) { & $addError "unknown placeholder {$tokenName} in $Where - not an engine token and not a variable of this workspace (declare it in the template's Variables or set it in the entry's Variables)" }
						return $Value
					}
					default { return $Value }
				}
			}

			# A plain loop over the matches rather than [regex]::Replace with a scriptblock evaluator:
			# turning a scriptblock into a MatchEvaluator compiles a delegate, which dominated the
			# first expansion of a shell's start.
			$text = [System.Text.StringBuilder]::new()
			$position = 0
			foreach ($match in [regex]::Matches($Value, $tokenPattern)) {
				[void]$text.Append($Value, $position, $match.Index - $position)
				$position = $match.Index + $match.Length
				$tokenName = $match.Groups[1].Value
				$found = & $lookup $tokenName
				$replacement = $match.Value
				if ($found.Kind -eq 'Value') {
					$tokenValue = $found.Value
					if (($tokenValue -is [System.Collections.IDictionary]) -or ($tokenValue -is [System.Collections.IList])) {
						& $addError "variable [$tokenName] holds a $(if ($tokenValue -is [System.Collections.IDictionary]) { 'hashtable' } else { 'list' }) and cannot be embedded in the text [$Value] in $Where - use it as the whole value (`"{$tokenName}`")"
					}
					else {
						$replacement = [string]$tokenValue
					}
				}
				elseif ($found.Kind -eq 'Unknown' -and $state.Strict) {
					& $addError "unknown placeholder {$tokenName} in $Where - not an engine token and not a variable of this workspace (declare it in the template's Variables or set it in the entry's Variables)"
				}
				[void]$text.Append($replacement)
			}
			[void]$text.Append($Value, $position, $Value.Length - $position)
			return $text.ToString()
		}
		if ($Value -is [System.Collections.IDictionary]) {
			$copy = @{}
			foreach ($key in $Value.Keys) { $copy[$key] = & $substitute $Value[$key] $Where }
			return $copy
		}
		if ($Value -is [System.Collections.IList]) {
			$items = @(foreach ($item in $Value) { , (& $substitute $item $Where) })
			return , $items
		}
		return $Value
	}

	$actionNameOf = { param($Entry) if ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('Action')) { ([string]$Entry['Action']).Trim() } else { '' } }
	$idOf = { param($Entry) if ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('Id') -and -not [string]::IsNullOrWhiteSpace([string]$Entry['Id'])) { ([string]$Entry['Id']).Trim() } else { '' } }

	# Finds the one action a name points at: an Id first, then an action name that must be unique.
	# Returns the index, -1 when nothing matches, -2 when the action name is ambiguous.
	$findTarget = {
		param([System.Collections.Generic.List[object]]$List, [string]$Key)
		for ($i = 0; $i -lt $List.Count; $i++) {
			if ((& $idOf $List[$i]) -ieq $Key) { return $i }
		}
		$byName = @(for ($i = 0; $i -lt $List.Count; $i++) { if ((& $actionNameOf $List[$i]) -ieq $Key) { $i } })
		if ($byName.Count -eq 1) { return $byName[0] }
		if ($byName.Count -gt 1) { return -2 }
		return -1
	}

	$result = [PSCustomObject]@{
		Name             = $Name
		IsTemplated      = $false
		Template         = ''
		Actions          = @()
		Changed          = $true
		VariableNames    = @()
		AppliedVariables = @()
		Errors           = @()
	}

	# ---------------------------------------------------------------------------------------
	# Plain entry: only {Workspace}, nothing is an error.
	# ---------------------------------------------------------------------------------------
	if (-not ($Definition -is [System.Collections.IDictionary])) {
		$plainActions = @($Definition | Where-Object { $null -ne $_ })
		if (-not (& $containsWorkspaceToken $plainActions)) {
			$result.Actions = $plainActions
			$result.Changed = $false
			return $result
		}
		$result.Actions = @(foreach ($action in $plainActions) { , (& $substitute $action "[$(& $actionNameOf $action)]") })
		return $result
	}

	# ---------------------------------------------------------------------------------------
	# Templated entry.
	# ---------------------------------------------------------------------------------------
	$state.Strict = $true
	$result.IsTemplated = $true

	foreach ($key in $Definition.Keys) {
		if ($entryKeys -notcontains [string]$key) {
			& $addError "unknown key [$key] - a templated entry takes $($entryKeys -join ', ')"
		}
	}

	$templateName = if ($Definition.Contains('Template')) { ([string]$Definition['Template']).Trim() } else { '' }
	$result.Template = $templateName
	if ([string]::IsNullOrWhiteSpace($templateName)) {
		& $addError "a hashtable entry is a templated workspace and needs Template = `"<name>`" (or write the entry as an action list)"
	}

	$template = $null
	if (-not [string]::IsNullOrWhiteSpace($templateName)) {
		if ($Templates -is [System.Collections.IDictionary]) {
			foreach ($candidateName in $Templates.Keys) {
				if ([string]$candidateName -ieq $templateName) { $template = $Templates[$candidateName]; break }
			}
		}
		if ($null -eq $template) {
			$known = if ($Templates -is [System.Collections.IDictionary] -and $Templates.Count -gt 0) { @($Templates.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join ', ' } else { 'none' }
			& $addError "unknown template [$templateName] (WorkspaceTemplates defines: $known)"
		}
		elseif (-not ($template -is [System.Collections.IDictionary])) {
			& $addError "template [$templateName] must be a hashtable with Variables and Actions"
			$template = $null
		}
	}

	if ($null -ne $template) {
		foreach ($key in $template.Keys) {
			if ($templateKeys -notcontains [string]$key) {
				& $addError "template [$templateName] has an unknown key [$key] - a template takes $($templateKeys -join ', ') (templates cannot extend other templates)"
			}
		}
	}

	# Declared variables: the template's defaults, then the entry's values.
	$declaredSources = @(
		@{ Label = "template [$templateName] Variables"; Value = $(if ($null -ne $template -and $template.Contains('Variables')) { $template['Variables'] }) }
		@{ Label = 'Variables'; Value = $(if ($Definition.Contains('Variables')) { $Definition['Variables'] }) }
	)
	foreach ($source in $declaredSources) {
		if ($null -eq $source.Value) { continue }
		if (-not ($source.Value -is [System.Collections.IDictionary])) {
			& $addError "$($source.Label) must be a hashtable of name = value"
			continue
		}
		foreach ($variableName in $source.Value.Keys) {
			$variableText = [string]$variableName
			if ($reservedNames -contains $variableText) {
				& $addError "$($source.Label) declares the reserved name [$variableText] ($($reservedNames -join ', ') are engine names)"
				continue
			}
			$state.Variables[$variableText] = $source.Value[$variableName]
		}
	}
	[string[]]$declaredNames = @($state.Variables.Keys)
	[Array]::Sort($declaredNames, [System.StringComparer]::OrdinalIgnoreCase)
	$result.VariableNames = $declaredNames

	if ($null -ne $Variables) {
		$applied = [System.Collections.Generic.List[string]]::new()
		foreach ($variableName in $Variables.Keys) {
			$variableText = [string]$variableName
			if ($state.Variables.ContainsKey($variableText)) {
				$state.Variables[$variableText] = $Variables[$variableName]
				$applied.Add($variableText)
			}
		}
		$result.AppliedVariables = $applied.ToArray()
	}

	if ($state.Errors.Count -gt 0 -or $null -eq $template) {
		$result.Errors = $state.Errors.ToArray()
		return $result
	}

	# 1. Copy the template's actions (copies, so Overrides and Add never reach into the configuration).
	# Variables are substituted last, over the final list only: an action the entry drops, or a
	# parameter it replaces, never reports a placeholder it no longer has.
	$templateActions = $template['Actions']
	if ($null -eq $templateActions -or -not ($templateActions -is [System.Collections.IList] -or $templateActions -is [System.Collections.IDictionary])) {
		& $addError "template [$templateName] needs Actions = @( <action entries> )"
		$result.Errors = $state.Errors.ToArray()
		return $result
	}

	$actions = [System.Collections.Generic.List[object]]::new()
	$fromTemplate = [System.Collections.Generic.HashSet[object]]::new()
	foreach ($templateAction in @($templateActions)) {
		if (-not ($templateAction -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace((& $actionNameOf $templateAction))) {
			& $addError "template [$templateName] has an action entry without Action"
			continue
		}
		$copy = & $copyDeep $templateAction
		$actions.Add($copy)
		[void]$fromTemplate.Add($copy)
	}

	$seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($action in $actions) {
		$actionId = & $idOf $action
		if ($actionId -and -not $seenIds.Add($actionId)) {
			& $addError "template [$templateName] uses the Id [$actionId] more than once"
		}
	}

	# 2. Overrides.
	$overrides = if ($Definition.Contains('Overrides')) { $Definition['Overrides'] } else { $null }
	if ($null -ne $overrides) {
		if (-not ($overrides -is [System.Collections.IDictionary])) {
			& $addError "Overrides must be a hashtable keyed by template action Id or action name"
		}
		else {
			$dropped = [System.Collections.Generic.List[object]]::new()
			foreach ($overrideKey in $overrides.Keys) {
				$overrideText = [string]$overrideKey
				$targetIndex = & $findTarget $actions $overrideText
				if ($targetIndex -eq -1) {
					& $addError "Overrides [$overrideText] matches no action of template [$templateName]"
					continue
				}
				if ($targetIndex -eq -2) {
					& $addError "Overrides [$overrideText] matches several actions of template [$templateName] - give them an Id in the template and override by Id"
					continue
				}

				$target = $actions[$targetIndex]
				$override = $overrides[$overrideKey]
				if ($override -is [System.Collections.IDictionary]) { $override = & $copyDeep $override }
				if ($null -eq $override) {
					$dropped.Add($target)
					continue
				}
				if (-not ($override -is [System.Collections.IDictionary])) {
					& $addError "Overrides [$overrideText] must be a hashtable ($($overrideKeys -join ', ')) or `$null to drop the action"
					continue
				}

				foreach ($key in $override.Keys) {
					$keyText = [string]$key
					$value = $override[$key]
					if ($keyText -in @('Action', 'Id')) {
						& $addError "Overrides [$overrideText] cannot change [$keyText] - drop the action with `$null and Add another one instead"
						continue
					}
					if ($overrideKeys -notcontains $keyText) {
						& $addError "Overrides [$overrideText] has an unknown key [$keyText] - an override takes $($overrideKeys -join ', ')"
						continue
					}

					if ($null -eq $value) {
						$target.Remove($keyText)
						continue
					}

					if ($keyText -eq 'Parameters' -or $tableKeys -contains $keyText) {
						if (-not ($value -is [System.Collections.IDictionary])) {
							& $addError "Overrides [$overrideText].$keyText must be a hashtable"
							continue
						}
						if (-not ($target[$keyText] -is [hashtable])) { $target[$keyText] = @{} }
						foreach ($innerKey in $value.Keys) {
							$innerValue = $value[$innerKey]
							# A parameter (or a whole table row) set to $null is removed. Deeper down a
							# $null is copied as data: inside a row it is the table's own "remove this
							# parameter on that machine/project".
							if ($null -eq $innerValue) {
								$target[$keyText].Remove($innerKey)
								continue
							}
							if ($target[$keyText].ContainsKey($innerKey) -and $target[$keyText][$innerKey] -is [System.Collections.IDictionary] -and $innerValue -is [System.Collections.IDictionary]) {
								if (-not ($target[$keyText][$innerKey] -is [hashtable])) { $target[$keyText][$innerKey] = & $copyDeep $target[$keyText][$innerKey] }
								& $mergeDeep $target[$keyText][$innerKey] $innerValue
							}
							else {
								$target[$keyText][$innerKey] = & $copyDeep $innerValue
							}
						}
						continue
					}

					$target[$keyText] = & $copyDeep $value
				}
			}
			foreach ($droppedAction in $dropped) { [void]$actions.Remove($droppedAction) }
		}
	}

	# 3. Add.
	$additions = if ($Definition.Contains('Add')) { $Definition['Add'] } else { $null }
	if ($null -ne $additions) {
		$additionList = if ($additions -is [System.Collections.IDictionary] -or $additions -is [System.Collections.IList]) { @($additions) } else { $null }
		if ($null -eq $additionList) {
			& $addError "Add must be a list of action entries"
		}
		else {
			foreach ($addition in $additionList) {
				$addedAction = & $actionNameOf $addition
				if (-not ($addition -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace($addedAction)) {
					& $addError "Add has an entry without Action"
					continue
				}
				$hasBefore = $addition.Contains('Before') -and -not [string]::IsNullOrWhiteSpace([string]$addition['Before'])
				$hasAfter = $addition.Contains('After') -and -not [string]::IsNullOrWhiteSpace([string]$addition['After'])
				if ($hasBefore -and $hasAfter) {
					& $addError "Add [$addedAction] sets both Before and After - use one"
					continue
				}

				$copy = & $copyDeep $addition
				$copy.Remove('Before')
				$copy.Remove('After')

				$insertAt = $actions.Count
				if ($hasBefore -or $hasAfter) {
					$anchor = if ($hasBefore) { ([string]$addition['Before']).Trim() } else { ([string]$addition['After']).Trim() }
					$anchorKey = if ($hasBefore) { 'Before' } else { 'After' }
					$anchorIndex = & $findTarget $actions $anchor
					if ($anchorIndex -eq -1) {
						& $addError "Add [$addedAction] $anchorKey [$anchor] matches no action of the workspace"
						continue
					}
					if ($anchorIndex -eq -2) {
						& $addError "Add [$addedAction] $anchorKey [$anchor] matches several actions - give the template action an Id and anchor on it"
						continue
					}
					$insertAt = if ($hasBefore) { $anchorIndex } else { $anchorIndex + 1 }
				}
				else {
					for ($i = 0; $i -lt $actions.Count; $i++) {
						if ($fromTemplate.Contains($actions[$i]) -and (& $actionNameOf $actions[$i]) -eq 'Set-WorkspaceWindowLayout') { $insertAt = $i; break }
					}
				}
				$actions.Insert($insertAt, $copy)
			}
		}
	}

	# 4. Variables over the final list, then the Id key (only a name for Overrides and Add) is dropped.
	$expanded = [System.Collections.Generic.List[object]]::new()
	foreach ($finalAction in $actions) {
		$action = & $substitute $finalAction "[$(& $actionNameOf $finalAction)]"
		$action.Remove('Id')
		if ([string]::IsNullOrWhiteSpace((& $actionNameOf $action))) {
			& $addError "an action resolves to an empty Action name"
			continue
		}
		$expanded.Add($action)
	}

	if ($state.Errors.Count -gt 0) {
		$result.Errors = @($state.Errors | Select-Object -Unique)
		return $result
	}

	$result.Actions = $expanded.ToArray()
	return $result
}

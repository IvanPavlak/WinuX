function Get-StartupTaskDefinitions {
	<#
	.SYNOPSIS
		Reads the startup tasks of the configuration, validated and with every default filled in.

	.DESCRIPTION
		The one place that knows the shape of a `Startup.Tasks` entry, so Invoke-StartupTasks
		(what runs), Set-StartupTasks (what Windows is told) and Register-StartupTaskPromptCheck
		(which open shells look again) can never disagree.

		A task is a hashtable. `Name` and `Trigger` are required, everything else is optional:

		- Name: unique; letters, digits, `-` and `_`. It names the task's stamp, lock and result
		  files and, for `Elevation = "Silent"`, its scheduled task.
		- Command: the command line to run, as typed at a prompt (aliases work). Without one the
		  task only opens a terminal.
		- Trigger: one or several of SignIn, Unlock, Wake and TerminalOpen. Boot is rejected:
		  nothing can run before sign-in with a desktop and the user's saved credentials.
		- Machine: a machine scope as everywhere else ("PC/Laptop", validated by
		  Test-MachineTypeScope). Hostname: one or several computer names. A task with neither
		  runs on every machine; with both, both must match.
		- Requires: names of `Startup.Conditions` entries the task waits for.
		- Window: Tab (default) or Hidden - where a SignIn, Unlock or Wake run happens. A
		  TerminalOpen run is always inline, in the shell that just opened.
		- KeepOpen: OnFailure (default), Always or Never - whether the task's tab stays. A task
		  without a Command defaults to Always.
		- Parallel: $true starts the task and moves on to the next without waiting for it.
		- Frequency: EveryTime (default), OncePerBoot, OncePerDay or Interval, with DayStartHour
		  (0-23, default 6) and IntervalHours (default 24).
		- Elevation: Relaunch, Prompt or Silent; absent (or None) means the task runs
		  unelevated. Prompt and Silent are refused on a task that has the TerminalOpen trigger.
		- Timeout: seconds the runner waits for the task before it moves on (default 600; 0
		  waits without limit). The task itself is never stopped.
		- Enabled: $false parks the task.

		An entry that breaks a rule - an unknown key, a missing or repeated Name, an unknown
		Trigger, Window, KeepOpen, Frequency or Elevation, a number out of range, a Requires name
		with no condition - is returned with Valid = $false and its Errors, and is never run:
		Invoke-StartupTasks reports it at every run.

		The deprecated automatic repository update is carried over: while
		`RepositoryUpdate.Startup.Enabled` is $true and no task is named RepositoryUpdate, one is
		added that does what the old hook did (TerminalOpen, once per day or per interval, the
		scope of `RepositoryUpdate.Startup.Scope`). It is marked Legacy. -IncludeLegacyDisabled
		adds it even when the key is off, for `Invoke-StartupRepositoryUpdate -Force`.

	.PARAMETER Name
		Return only the tasks with these names.

	.PARAMETER Trigger
		Return only the tasks that have this trigger.

	.PARAMETER Configuration
		The configuration to read `Startup` and `RepositoryUpdate.Startup` from. Defaults to
		$global:Configuration. The machine scope (Test-MachineTypeScope) and the groups of the
		carried-over repository update (Resolve-RepositoryUpdateScope) are always resolved
		against the loaded configuration.

	.PARAMETER IncludeLegacyDisabled
		Add the carried-over RepositoryUpdate task even when `RepositoryUpdate.Startup.Enabled`
		is not $true.

	.OUTPUTS
		[pscustomobject] per task, in configuration order: Name, Trigger (string[]), InScope
		(this machine), Valid, Errors (string[]), Legacy, and Parameters - the hashtable to splat
		onto Invoke-StartupTask (every option, without Trigger).

	.EXAMPLE
		Get-StartupTaskDefinitions | Format-Table Name, Trigger, InScope, Valid
		Every configured startup task and whether it applies to this machine.

	.EXAMPLE
		Get-StartupTaskDefinitions -Trigger SignIn | Where-Object { $_.Valid -and $_.InScope }
		The tasks a sign-in runs here.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[string[]]$Name,

		[Parameter()]
		[ValidateSet('SignIn', 'Unlock', 'Wake', 'TerminalOpen')]
		[string]$Trigger,

		[Parameter()]
		[AllowNull()]
		[object]$Configuration = $global:Configuration,

		[Parameter()]
		[switch]$IncludeLegacyDisabled
	)

	$validKeys = @('Name', 'Command', 'Trigger', 'Machine', 'Hostname', 'Requires', 'Window', 'KeepOpen', 'Parallel', 'Frequency', 'DayStartHour', 'IntervalHours', 'Elevation', 'Timeout', 'Enabled')
	$validTriggers = @('SignIn', 'Unlock', 'Wake', 'TerminalOpen')
	$validWindows = @('Tab', 'Hidden')
	$validKeepOpen = @('OnFailure', 'Always', 'Never')
	$validFrequencies = @('EveryTime', 'OncePerBoot', 'OncePerDay', 'Interval')
	$validElevations = @('None', 'Relaunch', 'Prompt', 'Silent')

	$conditions = Get-ConfigSetting -Path 'Startup.Conditions' -Default @{} -Configuration $Configuration
	$conditionNames = @()
	if ($conditions -is [System.Collections.IDictionary]) { $conditionNames = @($conditions.Keys | ForEach-Object { [string]$_ }) }

	$entries = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in @(Get-ConfigSetting -Path 'Startup.Tasks' -Default @() -Configuration $Configuration)) {
		if ($null -ne $entry) { $entries.Add($entry) }
	}

	# The deprecated RepositoryUpdate.Startup keys, carried over as one task unless the
	# configuration already defines a task of that name.
	$legacyName = 'RepositoryUpdate'
	$legacy = Get-ConfigSetting -Path 'RepositoryUpdate.Startup' -Configuration $Configuration
	$legacyEnabled = ($legacy -is [System.Collections.IDictionary]) -and [bool]$legacy['Enabled']
	$definesLegacyName = @($entries | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['Name'] -eq $legacyName }).Count -gt 0
	$legacyEntry = $null
	if (($legacyEnabled -or $IncludeLegacyDisabled) -and -not $definesLegacyName) {
		$scopePath = 'BootstrapConfig.RepositoryUpdateScope'
		if ($null -ne (Get-ConfigSetting -Path 'RepositoryUpdate.Startup.Scope' -Configuration $Configuration)) {
			$scopePath = 'RepositoryUpdate.Startup.Scope'
		}
		$scope = Resolve-RepositoryUpdateScope -Path $scopePath
		$legacyCommand = 'Update-Repositories -All -NoClone -Quiet'
		if ($scope -and -not $scope.All) {
			$groups = @($scope.Groups | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" }) -join ', '
			$legacyCommand = "Update-Repositories -Group $groups -NoClone -Quiet"
		}

		$legacyEntry = @{
			Name      = $legacyName
			Command   = $legacyCommand
			Trigger   = 'TerminalOpen'
			Frequency = 'OncePerDay'
			Enabled   = $legacyEnabled
		}
		if ($legacy -is [System.Collections.IDictionary]) {
			if ("$($legacy['Schedule'])" -eq 'Interval') { $legacyEntry.Frequency = 'Interval' }
			if ($null -ne $legacy['DayStartHour']) { $legacyEntry.DayStartHour = $legacy['DayStartHour'] }
			if ($null -ne $legacy['IntervalHours']) { $legacyEntry.IntervalHours = $legacy['IntervalHours'] }
		}
		$entries.Add($legacyEntry)
	}

	$seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$index = 0

	foreach ($entry in $entries) {
		$index++
		$errors = [System.Collections.Generic.List[string]]::new()
		$isLegacy = [object]::ReferenceEquals($entry, $legacyEntry)

		if (-not ($entry -is [System.Collections.IDictionary])) {
			if ($Name -or $Trigger) { continue }
			[pscustomobject]@{
				Name       = "#$index"
				Trigger    = @()
				InScope    = $false
				Valid      = $false
				Errors     = @("Startup.Tasks entry $index is not a hashtable")
				Legacy     = $false
				Parameters = @{}
			}
			continue
		}

		$taskName = ([string]$entry['Name']).Trim()
		$label = if ($taskName) { $taskName } else { "#$index" }

		if (-not $taskName) {
			$errors.Add("Name is missing")
		}
		elseif ($taskName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
			$errors.Add("Name [$taskName] may hold only letters, digits, '-' and '_'")
		}
		elseif (-not $seenNames.Add($taskName)) {
			$errors.Add("Name [$taskName] is used by an earlier task")
		}

		foreach ($key in @($entry.Keys)) {
			if ($validKeys -notcontains [string]$key) {
				$errors.Add("Unknown key [$key] - valid keys: $($validKeys -join ', ')")
			}
		}

		# Trigger: required, one or several; canonical spelling whatever the file's casing.
		$triggers = [System.Collections.Generic.List[string]]::new()
		$triggerRejected = $false
		foreach ($value in @($entry['Trigger'])) {
			$text = ([string]$value).Trim()
			if (-not $text) { continue }
			if ($text -eq 'Boot') {
				$errors.Add("Trigger [Boot] is not supported: nothing can run before sign-in with a desktop and your saved credentials - use SignIn")
				$triggerRejected = $true
				continue
			}
			$canonical = $validTriggers | Where-Object { $_ -eq $text } | Select-Object -First 1
			if (-not $canonical) {
				$errors.Add("Unknown Trigger [$text] - valid values: $($validTriggers -join ', ')")
				$triggerRejected = $true
				continue
			}
			if (-not $triggers.Contains($canonical)) { $triggers.Add($canonical) }
		}
		if ($triggers.Count -eq 0 -and -not $triggerRejected) {
			$errors.Add("Trigger is missing - one or several of: $($validTriggers -join ', ')")
		}

		$command = [string]$entry['Command']
		$hasCommand = -not [string]::IsNullOrWhiteSpace($command)

		$window = 'Tab'
		if ($null -ne $entry['Window']) {
			$canonical = $validWindows | Where-Object { $_ -eq [string]$entry['Window'] } | Select-Object -First 1
			if ($canonical) { $window = $canonical } else { $errors.Add("Unknown Window [$($entry['Window'])] - valid values: $($validWindows -join ', ') (a TerminalOpen run is always inline)") }
		}

		$keepOpen = if ($hasCommand) { 'OnFailure' } else { 'Always' }
		if ($null -ne $entry['KeepOpen']) {
			$canonical = $validKeepOpen | Where-Object { $_ -eq [string]$entry['KeepOpen'] } | Select-Object -First 1
			if ($canonical) { $keepOpen = $canonical } else { $errors.Add("Unknown KeepOpen [$($entry['KeepOpen'])] - valid values: $($validKeepOpen -join ', ')") }
		}

		$frequency = 'EveryTime'
		if ($null -ne $entry['Frequency']) {
			$canonical = $validFrequencies | Where-Object { $_ -eq [string]$entry['Frequency'] } | Select-Object -First 1
			if ($canonical) { $frequency = $canonical } else { $errors.Add("Unknown Frequency [$($entry['Frequency'])] - valid values: $($validFrequencies -join ', ')") }
		}

		$elevation = 'None'
		if ($null -ne $entry['Elevation'] -and -not [string]::IsNullOrWhiteSpace([string]$entry['Elevation'])) {
			$canonical = $validElevations | Where-Object { $_ -eq [string]$entry['Elevation'] } | Select-Object -First 1
			if ($canonical) { $elevation = $canonical } else { $errors.Add("Unknown Elevation [$($entry['Elevation'])] - valid values: None, Relaunch, Prompt, Silent") }
		}
		if ($elevation -in 'Prompt', 'Silent' -and $triggers.Contains('TerminalOpen')) {
			$errors.Add("Elevation [$elevation] cannot be combined with the TerminalOpen trigger - an inline run cannot be elevated; use Relaunch or a second task")
		}

		$dayStartHour = 6
		if ($null -ne $entry['DayStartHour']) {
			$hour = 0
			if ([int]::TryParse("$($entry['DayStartHour'])", [ref]$hour) -and $hour -ge 0 -and $hour -le 23) { $dayStartHour = $hour }
			elseif ($isLegacy) { $dayStartHour = 6 }
			else { $errors.Add("DayStartHour [$($entry['DayStartHour'])] is not an hour from 0 to 23") }
		}

		$intervalHours = 24.0
		if ($null -ne $entry['IntervalHours']) {
			$hours = 0.0
			if ([double]::TryParse("$($entry['IntervalHours'])", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$hours)) { $intervalHours = $hours }
			elseif ($isLegacy) { $intervalHours = 24.0 }
			else { $errors.Add("IntervalHours [$($entry['IntervalHours'])] is not a number") }
		}

		$timeout = 600.0
		if ($null -ne $entry['Timeout']) {
			$seconds = 0.0
			if ([double]::TryParse("$($entry['Timeout'])", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$seconds) -and $seconds -ge 0) { $timeout = $seconds }
			else { $errors.Add("Timeout [$($entry['Timeout'])] is not a number of seconds (0 or more)") }
		}

		$requires = @(@($entry['Requires']) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
		foreach ($required in $requires) {
			if (@($conditionNames | Where-Object { $_ -eq $required }).Count -eq 0) {
				$errors.Add("Requires names [$required], which is no Startup.Conditions entry")
			}
		}

		$hostnames = @(@($entry['Hostname']) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
		$machine = ([string]$entry['Machine']).Trim()

		$enabled = $true
		if ($null -ne $entry['Enabled']) { $enabled = [bool]$entry['Enabled'] }

		# Scope: the machine type (reported by Test-MachineTypeScope when a token is unknown)
		# and the computer name. Both must match when both are given.
		$inScope = $true
		if ($machine) { $inScope = [bool](Test-MachineTypeScope -Scope $machine -Context "Startup task [$label]") }
		if ($inScope -and $hostnames.Count -gt 0) { $inScope = $hostnames -contains $env:COMPUTERNAME }

		$parameters = @{
			Name          = $taskName
			Command       = $command
			Requires      = $requires
			Window        = $window
			KeepOpen      = $keepOpen
			Parallel      = [bool]$entry['Parallel']
			Frequency     = $frequency
			DayStartHour  = $dayStartHour
			IntervalHours = $intervalHours
			Elevation     = $elevation
			Timeout       = $timeout
			Enabled       = $enabled
		}
		if ($machine) { $parameters.Machine = $machine }
		if ($hostnames.Count -gt 0) { $parameters.Hostname = $hostnames }

		if ($Name -and @($Name | Where-Object { $_ -eq $label }).Count -eq 0) { continue }
		if ($Trigger -and $triggers -notcontains $Trigger) { continue }

		[pscustomobject]@{
			Name       = $label
			Trigger    = $triggers.ToArray()
			InScope    = $inScope
			Valid      = ($errors.Count -eq 0)
			Errors     = $errors.ToArray()
			Legacy     = $isLegacy
			Parameters = $parameters
		}
	}
}

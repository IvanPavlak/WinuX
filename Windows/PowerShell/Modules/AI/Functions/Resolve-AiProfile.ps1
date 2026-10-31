function Resolve-AiProfile {
	<#
	.SYNOPSIS
		Resolves the AI profile this machine runs: the WINUX_AI_PROFILE override, then the hostname map, then the default profile.

	.DESCRIPTION
		An AI profile is the per-machine set of AI choices every AI deploy function honours: the
		rules item, the Plan the managed settings pin, the harnesses, the artifacts it includes
		and excludes, the MCP servers and marketplaces it registers, whether unattended runs are
		allowed, and the repositories it owns. They live under AiProfiles in the configuration:

		  Hosts         hostname -> profile name
		  Default       the profile of a host the map does not name
		  Profiles      name -> @{ Rules; Plan; Deploy; Include; Exclude; McpServers;
		                Marketplaces; Unattended; Owns; Autonomous; EnvVars }
		  Shared        repository patterns every profile may work on
		  DefaultOwner  the profile owning a repository no pattern matches (default: Default)

		The profile is picked once per call: the WINUX_AI_PROFILE environment variable (an
		override naming no configured profile is reported and ignored), then this host's entry
		in Hosts, then Default. With no profile configured (the base configuration), or none
		that resolves, profiles are off: Enabled is $false and every AI function behaves as
		before, scoped by machine type.

		Repository patterns (Owns, Autonomous, Shared) are normalised the way the ownership guard
		normalises an origin remote: lowercase, no scheme, no user, no .git
		(github.com/my-org/*). Plan is one @{ Name; OrgUuid } or an array of them.
		McpServers and Marketplaces left out mean "all of them"; an empty list means none.

		Returns @{ Enabled; Name; Source; HostName; Profile; Profiles; Shared; DefaultOwner;
		Warnings }. Source is override, hostname or default (empty when off). Profile is the
		normalised active profile (Name; Rules; Plans; Deploy; Include; Exclude; McpServers;
		Marketplaces; Unattended; Owns; Autonomous; EnvVars), $null when off; Deploy,
		McpServers and Marketplaces are $null when the profile does not set them.

	.PARAMETER Configuration
		The configuration hashtable to read. Defaults to $global:Configuration.

	.PARAMETER HostName
		The hostname to look up. Defaults to $env:COMPUTERNAME.

	.PARAMETER Override
		The profile override. Defaults to $env:WINUX_AI_PROFILE.

	.EXAMPLE
		(Resolve-AiProfile).Name
		Returns the profile this machine runs, e.g. Personal.

	.EXAMPLE
		Resolve-AiProfile -HostName "WORKSTATION-01"
		Resolves the profile another host would run.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[string]$HostName = $env:COMPUTERNAME,

		[Parameter()]
		[AllowEmptyString()]
		[string]$Override = $env:WINUX_AI_PROFILE
	)

	$section = Get-ConfigSetting -Path 'AiProfiles' -Configuration $Configuration
	if ($section -isnot [hashtable]) { $section = @{} }
	$configured = if ($section.Profiles -is [hashtable]) { $section.Profiles } else { @{} }
	$hosts = if ($section.Hosts -is [hashtable]) { $section.Hosts } else { @{} }

	# host/owner/name, lowercase, no scheme, no user, no .git - the guard's normalisation.
	$normalise = {
		param([string]$Value)
		$text = $Value.Trim().ToLowerInvariant()
		$text = $text -replace '^[a-z+]+://', ''
		$text = $text -replace '^[^@/]+@', ''
		$text = $text -replace '^([^/:]+):([^0-9])', '$1/$2'
		$text = $text -replace '\.git/?$', ''
		$text.TrimEnd('/')
	}
	$patterns = {
		param($Value)
		@($Value | Where-Object { $_ } | ForEach-Object { & $normalise ([string]$_) } | Where-Object { $_ })
	}
	$strings = {
		param($Value)
		@($Value | Where-Object { $_ } | ForEach-Object { [string]$_ })
	}

	$result = @{
		Enabled      = $false
		Name         = ''
		Source       = ''
		HostName     = [string]$HostName
		Profile      = $null
		Profiles     = [ordered]@{}
		Shared       = @(& $patterns $section.Shared)
		DefaultOwner = ''
		Warnings     = @()
	}

	foreach ($name in ($configured.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $configured[$name]
		if ($entry -isnot [hashtable]) {
			$result.Warnings += "AiProfiles.Profiles.$name is not a hashtable - skipped"
			continue
		}
		$plans = @()
		# A configured Plan entry that cannot be used is kept as an error, not just dropped: the
		# managed settings must not be written without the pin the owner asked for.
		$planErrors = @()
		foreach ($plan in @($entry.Plan | Where-Object { $null -ne $_ })) {
			if ($plan -isnot [hashtable]) {
				$planErrors += "AiProfiles.Profiles.$name.Plan holds an entry that is not a hashtable"
				continue
			}
			$uuid = ([string]$plan.OrgUuid).Trim()
			if ($uuid -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
				$planErrors += "AiProfiles.Profiles.$name.Plan has an OrgUuid that is not a UUID => [$uuid]"
				continue
			}
			$planName = ([string]$plan.Name).Trim() -replace '\s+', '-'
			if (-not $planName) { $planName = 'Plan' }
			$plans += @{ Name = $planName; OrgUuid = $uuid.ToLowerInvariant() }
		}
		foreach ($planError in $planErrors) { $result.Warnings += $planError }
		$result.Profiles[$name] = @{
			Name         = $name
			Rules        = [string]$entry.Rules
			Plans        = $plans
			PlanErrors   = $planErrors
			Deploy       = if ($entry.ContainsKey('Deploy') -and $null -ne $entry.Deploy) { , @(& $strings $entry.Deploy) } else { $null }
			Include      = @(& $strings $entry.Include | ForEach-Object { $_.ToLowerInvariant() })
			Exclude      = @(& $strings $entry.Exclude | ForEach-Object { $_.ToLowerInvariant() })
			McpServers   = if ($entry.ContainsKey('McpServers') -and $null -ne $entry.McpServers) { , @(& $strings $entry.McpServers) } else { $null }
			Marketplaces = if ($entry.ContainsKey('Marketplaces') -and $null -ne $entry.Marketplaces) { , @(& $strings $entry.Marketplaces) } else { $null }
			Unattended   = [bool]$entry.Unattended
			Owns         = @(& $patterns $entry.Owns)
			Autonomous   = @(& $patterns $entry.Autonomous)
			EnvVars      = @(& $strings $entry.EnvVars)
		}
	}

	if ($result.Profiles.Count -eq 0) {
		return $result
	}

	# A configured name, matched case-insensitively, in its configured spelling.
	$find = {
		param([string]$Wanted)
		if (-not $Wanted) { return '' }
		$match = @($result.Profiles.Keys | Where-Object { $_ -eq $Wanted.Trim() }) | Select-Object -First 1
		if ($match) { return [string]$match }
		return ''
	}

	$default = & $find ([string]$section.Default)
	if ($section.Default -and -not $default) {
		$result.Warnings += "AiProfiles.Default names no configured profile => [$($section.Default)]"
	}
	$owner = & $find ([string]$section.DefaultOwner)
	if ($section.DefaultOwner -and -not $owner) {
		$result.Warnings += "AiProfiles.DefaultOwner names no configured profile => [$($section.DefaultOwner)]"
	}
	$result.DefaultOwner = if ($owner) { $owner } else { $default }

	$picked = ''
	if ($Override) {
		$picked = & $find $Override
		if ($picked) {
			$result.Source = 'override'
		}
		else {
			$result.Warnings += "WINUX_AI_PROFILE names no configured profile => [$Override] - ignored"
		}
	}
	if (-not $picked -and $HostName) {
		$hostKey = @($hosts.Keys | Where-Object { [string]$_ -eq $HostName }) | Select-Object -First 1
		if ($null -ne $hostKey) {
			$picked = & $find ([string]$hosts[$hostKey])
			if ($picked) {
				$result.Source = 'hostname'
			}
			else {
				$result.Warnings += "AiProfiles.Hosts.$hostKey names no configured profile => [$($hosts[$hostKey])]"
			}
		}
	}
	if (-not $picked -and $default) {
		$picked = $default
		$result.Source = 'default'
	}

	if ($picked) {
		$result.Enabled = $true
		$result.Name = $picked
		$result.Profile = $result.Profiles[$picked]
	}
	return $result
}

function Resolve-AiArtifactsConfig {
	<#
	.SYNOPSIS
		Resolves the AiArtifacts and AiHarnesses configuration sections into expanded, ready-to-use values for this machine type.

	.DESCRIPTION
		Reads `AiArtifacts` and `AiHarnesses` from the merged configuration and returns one
		hashtable the AI artifact functions share, so Deploy-AiArtifacts, Update-AiArtifacts and
		List-AiArtifacts agree on where the artifacts live, which apps get them and where:

		  Root        The artifacts root on disk (default {RepoRoot}\AI). Items live kind first:
		              <Root>\<Kind>\<source>\<item>.
		  Profile     The AI profile this machine runs (Resolve-AiProfile). With a profile
		              active its Rules wins over Use.Rules, its Deploy over AiArtifacts.Deploy,
		              its Exclude entries join the global ones and its Include entries limit
		              the kinds they name.
		  Include     The active profile's Include entries, lowercased (empty: everything).
		  Checkouts   The checkout sources, name -> @{ Name; Path; Kinds }: a local repository
		              whose items are linked straight from it (Kinds as for Sources, default
		              skills = @("skills")).
		  Manifests   The manifest sources, name -> @{ Name; Path }: a manifest file whose rows
		              are cloned into CacheRoot and linked from there.
		  CacheRoot   Where manifest refs are cloned: %LOCALAPPDATA%\WinuX\ai-manifests.
		  Sources     The vendored sources, name -> @{ Repository; Ref; Kinds; Exclude;
		              SkipPaths }, Kinds an ordered map of kind (skills, mods, rules, prompts,
		              agents) -> upstream folders. A source without a kind key gets
		              skills = @("skills").
		  Exclude     The Exclude entries for this machine type, lowercased: kind/name or
		              kind/source/name.
		  Use         Kind -> the item name a File destination takes, for this machine type.
		  Deploy      The AiHarnesses names AiArtifacts.Deploy lists for this machine type (its
		              own key, else Default).
		  Harnesses   Ordered name -> @{ Name; WSL; Destinations }, one per Deploy name that has
		              an AiHarnesses entry; each destination is @{ Kind; Placement; Files;
		              Hooks; Path; WSLPath } with the kind, placement and hooks lowercased, the
		              placeholders expanded and only the destinations whose Machine scope
		              matches. WSLPath is the WSL twin: the destination's own WSLPath, else the
		              {User} path mapped onto /home/<DefaultWSLUsername>; empty without a WSL
		              twin.
		  Unknown     Deploy names that have no AiHarnesses entry.
		  WSLUser     DefaultWSLUsername, empty when not configured.

		Only the {User}, {RepoRoot}, {AppData} and {Dev} placeholders are expanded here ({Dev}
		is BasePaths.<MachineType>.Dev, else the folder holding the repository) - the sections
		are machine-type independent apart from the scopes, so they do not go through
		Expand-ConfigPaths. Every key falls back to the built-in default when missing, so the
		empty base configuration resolves to a usable setup that deploys nothing.

	.PARAMETER Configuration
		The configuration hashtable to read. Defaults to $global:Configuration.

	.PARAMETER RepoRoot
		Repository root used for {RepoRoot}. Defaults to Get-RepositoryPath.

	.PARAMETER MachineType
		The machine type whose Deploy, Exclude, Use and destination scopes apply. Defaults to
		$global:MachineType.

	.PARAMETER AiProfile
		A resolved AI profile (Resolve-AiProfile). Defaults to resolving it from the same
		configuration.

	.EXAMPLE
		(Resolve-AiArtifactsConfig).Deploy
		Returns the harnesses this machine deploys into, e.g. claude-code, codex.

	.EXAMPLE
		(Resolve-AiArtifactsConfig -MachineType Work).Harnesses['claude-code'].Destinations
		Returns the expanded destinations of Claude Code on a Work machine.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[string]$RepoRoot,

		[Parameter()]
		[string]$MachineType = $global:MachineType,

		[Parameter()]
		[hashtable]$AiProfile
	)

	if (-not $RepoRoot) {
		$RepoRoot = (Get-RepositoryPath).Repo
	}

	$kinds = @('skills', 'mods', 'rules', 'prompts', 'agents')

	$section = Get-ConfigSetting -Path 'AiArtifacts' -Configuration $Configuration
	if ($section -isnot [hashtable]) { $section = @{} }
	$harnessSection = Get-ConfigSetting -Path 'AiHarnesses' -Configuration $Configuration
	if ($harnessSection -isnot [hashtable]) { $harnessSection = @{} }

	if (-not $AiProfile) {
		$AiProfile = Resolve-AiProfile -Configuration $Configuration
	}
	$active = if ($AiProfile.Enabled) { $AiProfile.Profile } else { $null }

	$userProfile = $env:USERPROFILE
	$devRoot = ''
	if ($MachineType) {
		$devRoot = [Environment]::ExpandEnvironmentVariables([string](Get-ConfigSetting -Path "BasePaths.$MachineType.Dev" -Default '' -Configuration $Configuration))
	}
	if (-not $devRoot) { $devRoot = Split-Path -Path $RepoRoot.TrimEnd('\') -Parent }
	$expand = {
		param($value)
		([string]$value).Replace('{RepoRoot}', $RepoRoot).Replace('{User}', $userProfile).Replace('{AppData}', $env:APPDATA).Replace('{Dev}', $devRoot)
	}

	# A value that may be written per machine type: @{ Default = ...; Work = ... }.
	$forMachine = {
		param($value)
		if ($value -is [hashtable] -and ($value.ContainsKey('Default') -or ($MachineType -and $value.ContainsKey($MachineType)))) {
			if ($MachineType -and $value.ContainsKey($MachineType)) { return , $value[$MachineType] }
			return , $value['Default']
		}
		return , $value
	}

	$defaultRoot = "{RepoRoot}\AI"
	$rootTemplate = if ($section.Root) { [string]$section.Root } else { $defaultRoot }

	# Sources: name -> repository, ref, kind folders, Exclude and SkipPaths.
	$sources = [ordered]@{}
	$configuredSources = if ($section.Sources -is [hashtable]) { $section.Sources } else { @{} }
	foreach ($name in ($configuredSources.Keys | Sort-Object)) {
		$entry = $configuredSources[$name]
		if ($entry -isnot [hashtable]) { continue }
		$kindMap = [ordered]@{}
		foreach ($kind in $kinds) {
			foreach ($key in @($entry.Keys)) {
				if ([string]$key -eq $kind -and $null -ne $entry[$key]) { $kindMap[$kind] = @($entry[$key] | ForEach-Object { [string]$_ }) }
			}
		}
		if ($kindMap.Count -eq 0) { $kindMap['skills'] = @('skills') }
		$sources[[string]$name] = @{
			Repository = [string]$entry.Repository
			Ref        = if ($entry.Ref) { [string]$entry.Ref } else { 'main' }
			Kinds      = $kindMap
			Exclude    = if ($entry.Exclude) { @($entry.Exclude | ForEach-Object { [string]$_ }) } else { @() }
			SkipPaths  = if ($entry.ContainsKey('SkipPaths') -and $null -ne $entry.SkipPaths) { @($entry.SkipPaths | ForEach-Object { [string]$_ }) } else { @('.git', '.github', 'tests', 'design', 'docs') }
		}
	}

	# Exclude: strings, or @{ Item = "kind/name"; Machine = "PC/Work" } for one machine scope.
	$exclude = @()
	foreach ($entry in @($section.Exclude)) {
		if ($null -eq $entry) { continue }
		if ($entry -is [hashtable]) {
			if (-not $entry.Item) { continue }
			if ($entry.Machine -and -not (Test-MachineTypeScope -Scope ([string]$entry.Machine) -MachineType $MachineType -Context "AiArtifacts.Exclude")) { continue }
			$exclude += ([string]$entry.Item).ToLowerInvariant()
			continue
		}
		if ([string]$entry) { $exclude += ([string]$entry).ToLowerInvariant() }
	}
	if ($active) {
		$exclude += @($active.Exclude)
	}
	$include = if ($active) { @($active.Include) } else { @() }

	# Checkout sources: a local repository linked straight from its folders.
	$checkouts = [ordered]@{}
	$configuredCheckouts = if ($section.Checkouts -is [hashtable]) { $section.Checkouts } else { @{} }
	foreach ($name in ($configuredCheckouts.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $configuredCheckouts[$name]
		if ($entry -isnot [hashtable] -or -not $entry.Path) { continue }
		$kindMap = [ordered]@{}
		foreach ($kind in $kinds) {
			foreach ($key in @($entry.Keys)) {
				if ([string]$key -eq $kind -and $null -ne $entry[$key]) { $kindMap[$kind] = @($entry[$key] | ForEach-Object { [string]$_ }) }
			}
		}
		if ($kindMap.Count -eq 0) { $kindMap['skills'] = @('skills') }
		$checkouts[$name] = @{
			Name  = $name
			Path  = (& $expand $entry.Path).TrimEnd('\')
			Kinds = $kindMap
		}
	}

	# Manifest sources: a manifest file whose pinned rows are cloned into the cache.
	$manifests = [ordered]@{}
	$configuredManifests = if ($section.Manifests -is [hashtable]) { $section.Manifests } else { @{} }
	foreach ($name in ($configuredManifests.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $configuredManifests[$name]
		$manifestPath = if ($entry -is [hashtable]) { [string]$entry.Path } else { [string]$entry }
		if (-not $manifestPath) { continue }
		$manifests[$name] = @{
			Name = $name
			Path = & $expand $manifestPath
		}
	}
	$localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $userProfile 'AppData\Local' }
	$cacheRoot = Join-Path $localAppData 'WinuX\ai-manifests'

	# Use: kind -> item name, each value optionally per machine type.
	$use = @{}
	if ($section.Use -is [hashtable]) {
		foreach ($key in $section.Use.Keys) {
			$value = & $forMachine $section.Use[$key]
			if ($value -and $kinds -contains ([string]$key).ToLowerInvariant()) {
				$use[([string]$key).ToLowerInvariant()] = [string]$value
			}
		}
	}

	# The active profile's rules item wins over Use.Rules.
	if ($active -and $active.Rules) {
		$use['rules'] = [string]$active.Rules
	}

	# Deploy: the active profile's harnesses, else this machine type's.
	$deploy = @()
	if ($active -and $null -ne $active.Deploy) {
		$deploy = @($active.Deploy | Where-Object { $_ } | ForEach-Object { [string]$_ })
	}
	elseif ($section.Deploy -is [hashtable]) {
		if ($MachineType -and $section.Deploy.ContainsKey($MachineType)) {
			$deploy = @($section.Deploy[$MachineType] | Where-Object { $_ } | ForEach-Object { [string]$_ })
		}
		elseif ($section.Deploy.ContainsKey('Default')) {
			$deploy = @($section.Deploy['Default'] | Where-Object { $_ } | ForEach-Object { [string]$_ })
		}
	}
	elseif ($section.Deploy) {
		$deploy = @($section.Deploy | Where-Object { $_ } | ForEach-Object { [string]$_ })
	}

	$wslUser = [string](Get-ConfigSetting -Path 'DefaultWSLUsername' -Default '' -Configuration $Configuration)

	$harnesses = [ordered]@{}
	$unknown = @()
	foreach ($name in $deploy) {
		$key = @($harnessSection.Keys | Where-Object { [string]$_ -eq $name }) | Select-Object -First 1
		if ($null -eq $key -or $harnessSection[$key] -isnot [hashtable]) {
			$unknown += $name
			continue
		}
		if ($harnesses.Contains([string]$key)) { continue }
		$definition = $harnessSection[$key]
		$wsl = [bool]$definition.WSL
		$destinations = @()
		foreach ($destination in @($definition.Destinations)) {
			if ($destination -isnot [hashtable]) { continue }
			if ($destination.Machine -and -not (Test-MachineTypeScope -Scope ([string]$destination.Machine) -MachineType $MachineType -Context "AiHarnesses.$key")) { continue }
			$pathTemplate = [string]$destination.Path
			$wslPath = ''
			if ($wsl -and $wslUser) {
				if ($destination.WSLPath) {
					$wslPath = [string]$destination.WSLPath
				}
				elseif ($pathTemplate.StartsWith('{User}\')) {
					$wslPath = "/home/$wslUser/" + $pathTemplate.Substring('{User}\'.Length).Replace('\', '/')
				}
			}
			$destinations += @{
				Kind      = ([string]$destination.Kind).ToLowerInvariant()
				Placement = ([string]$destination.Placement).ToLowerInvariant()
				Files     = @($destination.Files | Where-Object { $_ } | ForEach-Object { [string]$_ })
				Hooks     = @($destination.Hooks | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
				Path      = if ($pathTemplate) { & $expand $pathTemplate } else { '' }
				WSLPath   = $wslPath
			}
		}
		$harnesses[[string]$key] = @{
			Name         = [string]$key
			WSL          = $wsl
			Destinations = $destinations
		}
	}

	return @{
		Root      = & $expand $rootTemplate
		Sources   = $sources
		Checkouts = $checkouts
		Manifests = $manifests
		CacheRoot = $cacheRoot
		Exclude   = $exclude
		Include   = $include
		Use       = $use
		Deploy    = $deploy
		Harnesses = $harnesses
		Unknown   = $unknown
		WSLUser   = $wslUser
		Profile   = $AiProfile
	}
}

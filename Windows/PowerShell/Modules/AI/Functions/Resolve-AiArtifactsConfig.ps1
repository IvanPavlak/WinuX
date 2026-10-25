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
		  Legacy      One message per deprecated key that was mapped (1.6.0, removed in 2.0.0).

		Deprecated keys are read and mapped, so a fork that has not migrated keeps working:
		AiSkills.Sources become sources with Skills = Folders, AiMods.Sources sources with
		Mods = Folders (default "."), Exclude and SkipPaths; an AiArtifacts.Sources entry of the
		same name wins. An AiSkills or AiMods Root other than the shipped default moves Root to
		its parent folder while Root itself is the default. A Rules item a
		PathTemplates.SymbolicLinks.AI entry targets becomes Use.Rules when Use names none. When
		Deploy lists nothing for this machine type but a deprecated step (CoreAiRules, AiSkills,
		AiMods) is on, or a deprecated Sources key is set, Deploy is claude-code, codex and
		gemini-cli - the folders the old commands wrote.

		Only the {User}, {RepoRoot} and {AppData} placeholders are expanded here - the sections
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
		[string]$MachineType = $global:MachineType
	)

	if (-not $RepoRoot) {
		$RepoRoot = (Get-RepositoryPath).Repo
	}

	$kinds = @('skills', 'mods', 'rules', 'prompts', 'agents')
	$legacy = [System.Collections.Generic.List[string]]::new()

	$section = Get-ConfigSetting -Path 'AiArtifacts' -Configuration $Configuration
	if ($section -isnot [hashtable]) { $section = @{} }
	$harnessSection = Get-ConfigSetting -Path 'AiHarnesses' -Configuration $Configuration
	if ($harnessSection -isnot [hashtable]) { $harnessSection = @{} }

	$userProfile = $env:USERPROFILE
	$expand = {
		param($value)
		([string]$value).Replace('{RepoRoot}', $RepoRoot).Replace('{User}', $userProfile).Replace('{AppData}', $env:APPDATA)
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

	# Root, with a deprecated AiSkills / AiMods Root mapped onto its parent folder.
	$defaultRoot = "{RepoRoot}\AI"
	$rootTemplate = if ($section.Root) { [string]$section.Root } else { $defaultRoot }
	foreach ($old in @(@{ Key = 'AiSkills'; Default = "{RepoRoot}\AI\Skills"; Leaf = 'Skills' }, @{ Key = 'AiMods'; Default = "{RepoRoot}\AI\Mods"; Leaf = 'Mods' })) {
		$oldRoot = [string](Get-ConfigSetting -Path "$($old.Key).Root" -Default '' -Configuration $Configuration)
		if (-not $oldRoot -or $oldRoot.TrimEnd('\') -eq $old.Default) { continue }
		if ($rootTemplate -eq $defaultRoot -and (Split-Path -Path $oldRoot.TrimEnd('\') -Leaf) -eq $old.Leaf) {
			$rootTemplate = Split-Path -Path $oldRoot.TrimEnd('\') -Parent
			$legacy.Add("$($old.Key).Root is deprecated - read as AiArtifacts.Root = `"$rootTemplate`"")
		}
		else {
			$legacy.Add("$($old.Key).Root is deprecated and not read - items live under AiArtifacts.Root\$($old.Leaf)")
		}
	}

	# Sources: AiArtifacts first, then the deprecated AiSkills and AiMods sources mapped onto
	# names AiArtifacts does not define.
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

	$legacySources = $false
	foreach ($old in @(@{ Key = 'AiSkills'; Kind = 'skills'; Folders = @('skills') }, @{ Key = 'AiMods'; Kind = 'mods'; Folders = @('.') })) {
		$oldSources = Get-ConfigSetting -Path "$($old.Key).Sources" -Configuration $Configuration
		if ($oldSources -isnot [hashtable] -or $oldSources.Count -eq 0) { continue }
		foreach ($name in ($oldSources.Keys | Sort-Object)) {
			$entry = $oldSources[$name]
			if ($entry -isnot [hashtable]) { continue }
			if ($configuredSources.ContainsKey($name)) { continue }
			$legacySources = $true
			$folders = if ($entry.Folders) { @($entry.Folders | ForEach-Object { [string]$_ }) } else { $old.Folders }
			if (-not $sources.Contains([string]$name)) {
				$sources[[string]$name] = @{
					Repository = [string]$entry.Repository
					Ref        = if ($entry.Ref) { [string]$entry.Ref } else { 'main' }
					Kinds      = [ordered]@{}
					Exclude    = @()
					SkipPaths  = @('.git', '.github', 'tests', 'design', 'docs')
				}
			}
			$mapped = $sources[[string]$name]
			$mapped.Kinds[$old.Kind] = $folders
			if ($entry.Exclude) { $mapped.Exclude = @(@($mapped.Exclude) + @($entry.Exclude | ForEach-Object { [string]$_ }) | Select-Object -Unique) }
			if ($entry.ContainsKey('SkipPaths') -and $null -ne $entry.SkipPaths) { $mapped.SkipPaths = @($entry.SkipPaths | ForEach-Object { [string]$_ }) }
			$foldersText = ($folders | ForEach-Object { '"' + $_ + '"' }) -join ', '
			$kindKey = (Get-Culture).TextInfo.ToTitleCase($old.Kind)
			$legacy.Add("$($old.Key).Sources.$name is deprecated - read as AiArtifacts.Sources.$name with $kindKey = @($foldersText)")
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
	if (-not $use.ContainsKey('rules')) {
		$aiLinks = Get-ConfigSetting -Path 'PathTemplates.SymbolicLinks.AI' -Configuration $Configuration
		if ($aiLinks -is [hashtable]) {
			foreach ($link in $aiLinks.Values) {
				if ($link -is [hashtable] -and ([string]$link.Target) -match '[\\/]AI[\\/]Rules[\\/][^\\/]+[\\/]([^\\/]+)[\\/]') {
					$use['rules'] = $Matches[1]
					$legacy.Add("PathTemplates.SymbolicLinks.AI is deprecated - its rules item is read as AiArtifacts.Use.Rules = `"$($Matches[1])`"")
					break
				}
			}
		}
	}

	# Deploy: this machine type's harnesses; the deprecated steps and sources imply the
	# folders the old commands wrote.
	$deploy = @()
	if ($section.Deploy -is [hashtable]) {
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
	if ($deploy.Count -eq 0) {
		$legacySteps = @()
		$steps = Get-ConfigSetting -Path 'BootstrapConfig.Steps' -Configuration $Configuration
		if ($steps -is [hashtable]) {
			foreach ($stepName in @('CoreAiRules', 'AiSkills', 'AiMods')) {
				if (-not $steps.ContainsKey($stepName)) { continue }
				if ([bool](& $forMachine $steps[$stepName])) { $legacySteps += $stepName }
			}
		}
		if ($legacySteps.Count -gt 0 -or $legacySources) {
			$deploy = @('claude-code', 'codex', 'gemini-cli')
			$reason = if ($legacySteps.Count -gt 0) { "BootstrapConfig.Steps.$($legacySteps -join ', ')" } else { "AiSkills / AiMods Sources" }
			$legacy.Add("AiArtifacts.Deploy lists no harness for this machine type - deploying into claude-code, codex and gemini-cli (the folders the deprecated $reason used); set AiArtifacts.Deploy")
		}
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
		Exclude   = $exclude
		Use       = $use
		Deploy    = $deploy
		Harnesses = $harnesses
		Unknown   = $unknown
		WSLUser   = $wslUser
		Legacy    = [string[]]$legacy.ToArray()
	}
}

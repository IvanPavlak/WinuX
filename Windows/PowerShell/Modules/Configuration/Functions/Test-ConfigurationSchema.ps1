function Test-ConfigurationSchema {
	<#
	.SYNOPSIS
		Validates that all required keys are present in the loaded configuration.

	.DESCRIPTION
		Checks the global $Configuration hashtable for the presence and non-null/non-empty
		values of every key required by core module functions. Collects every problem and
		reports them together as one warning. Without -Strict it does not throw - missing keys
		produce a warning so the shell can still start with a degraded configuration rather
		than failing entirely; with -Strict the same report is thrown as a terminating error.

		Only FRAMEWORK keys are required. User-specific sections (themes, wallpapers,
		locale, keyboard layouts, Wake-on-LAN, taskbar pins, ...) ship empty by design
		and their consumers no-op with a warning, so an untouched vanilla configuration
		is valid. The exception is GitConfig.UserName/UserEmail, which the base ships
		blank and Initialize-Configuration fills into Configuration.local.psd1 on the
		first run - they warn until then.

		On top of the presence checks it validates the SHAPE of the ordered sections -
		the ones whose entries become a menu (see the ordering rule in Configuration.psd1).
		Each must be an array of single-key hashtables; a plain hashtable is reported,
		because Import-PowerShellDataFile loses key order and its menu would be sorted
		rather than following the file.

		It also validates workspace templates: WorkspaceTemplates must be a hashtable of templates
		that each carry Actions, and every templated WorkspaceActions entry must expand cleanly
		through Resolve-WorkspaceTemplate - an unknown template, a variable without a value, an
		ambiguous or unmatched override, an unknown placeholder, a variable cycle or a bad Before /
		After anchor is reported with the workspace named.

		It validates the AI artifact sections: AiArtifacts.Deploy names only AiHarnesses entries,
		its Use and Exclude entries name a kind (Skills, Mods, Rules, Prompts, Agents), and every
		AiHarnesses destination carries a known Kind and Placement (Each, Copy, File), Files and
		Path.

		Finally it reports deprecated configuration (VERSIONING.md, Deprecation policy): one
		warning per deprecated key or step name the merged configuration still uses, naming the
		release that deprecated it, the release that removes it and its replacement. The table of
		deprecations is the $deprecations list at the top of this function - the only thing a
		later deprecation adds to. A deprecation never counts as a failure, even under -Strict:
		the old shape keeps working until the next MAJOR. A key that the base Configuration.psd1
		still ships only warns when it is set to something other than the shipped default
		(NotDefault), so a vanilla configuration stays silent. The table is empty while nothing
		is deprecated.

		Call this function immediately after Load-PathConfiguration during the bootstrap
		or profile initialization sequence to surface typos and missing entries early; the
		profile does so at every load and Bootstrap at the start of every run.

	.PARAMETER Configuration
		The configuration hashtable to validate. Defaults to $global:Configuration.

	.PARAMETER Strict
		If specified, throws a terminating error when any required key is missing.
		Use during bootstrap/testing; omit for profile startup (warning-only).

	.EXAMPLE
		Test-ConfigurationSchema
		Validates $global:Configuration and writes a warning for each missing key.

	.EXAMPLE
		Test-ConfigurationSchema -Strict
		Throws if any required key is absent (suitable for bootstrap validation).

	.EXAMPLE
		Test-ConfigurationSchema -Configuration $myConfig
		Validates a specific configuration hashtable rather than the global one.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[switch]$Strict
	)

	# Deprecated configuration: Path (dotted), Since, Removal, Replacement and When - Present
	# (the key exists), NotEmpty (Test-ConfigValue) or NotDefault (differs from Default, the
	# value the base Configuration.psd1 ships; an array compares element by element).
	# Empty while nothing is deprecated; a later deprecation adds one entry per key, e.g.
	#   @{ Path = 'Section.OldKey'; Since = '2.1.0'; Removal = '3.0.0'; When = 'Present'; Replacement = 'Section.NewKey' }
	$deprecations = @()

	$failures = [System.Collections.Generic.List[string]]::new()

	if ($null -eq $Configuration) {
		$msg = "Configuration is null - Load-PathConfiguration may not have run."
		if ($Strict) { throw $msg } else { Write-Warning $msg ; return }
	}

	# Required top-level keys and nested paths: [description, key-path-array]
	#
	# Only FRAMEWORK keys belong here - the ones the engine cannot resolve paths or
	# detect a machine without. Everything user-specific ships empty by design (see the
	# empty-by-default philosophy in Configuration.psd1) and its consumer no-ops with a
	# warning, so requiring it here would flag a correct vanilla install as broken.
	$requiredKeys = @(
		# Machine detection
		@{ Desc = "ValidMachineTypes"; Path = @('ValidMachineTypes') }
		@{ Desc = "HostnameToMachineType"; Path = @('HostnameToMachineType') }
		@{ Desc = "DefaultMachineType"; Path = @('DefaultMachineType') }
		@{ Desc = "LaptopChassisTypes"; Path = @('LaptopChassisTypes') }

		# Path system
		@{ Desc = "BasePaths"; Path = @('BasePaths') }
		@{ Desc = "PathTemplates"; Path = @('PathTemplates') }
		@{ Desc = "Projects.Self.Root"; Path = @('PathTemplates', 'Projects', 'Self', 'Root') }

		# Git
		@{ Desc = "GitConfig.UserName"; Path = @('GitConfig', 'UserName') }
		@{ Desc = "GitConfig.UserEmail"; Path = @('GitConfig', 'UserEmail') }
		@{ Desc = "GitConfig.WingetPackageId"; Path = @('GitConfig', 'WingetPackageId') }

		# Locale, keyboard layouts and display language are NOT required: they ship
		# empty and Set-Locale / Set-KeyboardLayouts / Set-DisplayLanguage leave the
		# system as-is until a fork opts in via Configuration.local.psd1.

		# Application paths
		@{ Desc = "BrowserGroups"; Path = @('BrowserGroups') }
		@{ Desc = "PathTemplates.SymbolicLinks"; Path = @('PathTemplates', 'SymbolicLinks') }
		@{ Desc = "RepositoryGroups"; Path = @('RepositoryGroups') }
	)

	foreach ($entry in $requiredKeys) {
		if (-not (Test-ConfigurationKeyPath -Table $Configuration -Path $entry.Path)) {
			$failures.Add("Missing or empty required key: $($entry.Desc)")
		}
	}

	# Ordered sections: an array of single-key hashtables, one per entry, so the menu
	# follows the file. Only checked when configured - every one of them may ship empty.
	$orderedSections = @(
		'BrowserGroups'
		'RepositoryGroups'
		'ProjectActions'
		'WorkspaceActions'
		'CampaignResources'
		'AcrobatPdfGroups'
		'WakeOnLanConfig'
		'Locales'
		'KeyboardLayoutSets'
		'NerdFonts'
	)

	foreach ($section in $orderedSections) {
		$value = $Configuration[$section]
		if (-not (Test-ConfigValue $value)) {
			continue
		}

		if ($value -is [System.Collections.IDictionary]) {
			$failures.Add("$section is a hashtable - entry order is lost at load time. Write it as an ordered array of single-key hashtables: @( @{ Name = <entry> } ... )")
			continue
		}

		$badEntries = @($value | Where-Object { $_ -isnot [System.Collections.IDictionary] -or $_.Count -ne 1 })
		if ($badEntries.Count -gt 0) {
			$failures.Add("$section has $($badEntries.Count) entr(y/ies) that are not single-key hashtables - each entry is @{ Name = <entry> }")
		}
	}

	# Workspace templates: the section's shape, then every templated WorkspaceActions entry
	# (unknown template, missing variable, ambiguous override, unknown placeholder, variable
	# cycle, bad Before / After anchor - everything Resolve-WorkspaceTemplate reports). Entries
	# Load-PathConfiguration already expanded (WorkspaceTemplateEntries) are not expanded a second
	# time: their problems were recorded under WorkspaceTemplateErrors. Templated entries still
	# present in WorkspaceActions (a configuration that was never expanded) are resolved here.
	$workspaceTemplates = $Configuration['WorkspaceTemplates']
	if ($null -ne $workspaceTemplates) {
		if (-not ($workspaceTemplates -is [System.Collections.IDictionary])) {
			$failures.Add("WorkspaceTemplates must be a hashtable of template name => @{ Variables = @{ ... }; Actions = @( ... ) }")
		}
		else {
			foreach ($templateName in $workspaceTemplates.Keys) {
				$template = $workspaceTemplates[$templateName]
				if (-not ($template -is [System.Collections.IDictionary]) -or -not $template.Contains('Actions')) {
					$failures.Add("WorkspaceTemplates.$templateName needs Actions = @( <action entries> )")
				}
			}
		}
	}

	foreach ($message in @($Configuration['WorkspaceTemplateErrors'])) {
		if (-not [string]::IsNullOrWhiteSpace([string]$message)) { $failures.Add([string]$message) }
	}

	$templatedEntries = [ordered]@{}
	$workspaceSection = $Configuration['WorkspaceActions']
	# An ordered array of single-key hashtables, or a legacy hashtable - one item either way.
	foreach ($workspaceItem in @($workspaceSection)) {
		if (-not ($workspaceItem -is [System.Collections.IDictionary])) { continue }
		foreach ($entryName in $workspaceItem.Keys) {
			if ($workspaceItem[$entryName] -is [System.Collections.IDictionary]) {
				$templatedEntries[[string]$entryName] = $workspaceItem[$entryName]
			}
		}
	}

	if ($templatedEntries.Count -gt 0 -and (Get-Command Resolve-WorkspaceTemplate -ErrorAction SilentlyContinue)) {
		foreach ($entryName in $templatedEntries.Keys) {
			$resolution = Resolve-WorkspaceTemplate -Name $entryName -Definition $templatedEntries[$entryName] -Templates $workspaceTemplates
			foreach ($message in @($resolution.Errors)) { $failures.Add($message) }
		}
	}

	# AI artifacts: AiArtifacts.Deploy names AiHarnesses entries; Use and Exclude name a kind;
	# every harness destination is complete. Only checked when the sections are present.
	$aiKinds = @('skills', 'mods', 'rules', 'prompts', 'agents')
	$aiHarnesses = $Configuration['AiHarnesses']
	if ($null -ne $aiHarnesses) {
		if (-not ($aiHarnesses -is [System.Collections.IDictionary])) {
			$failures.Add("AiHarnesses must be a hashtable of harness name => @{ WSL = `$true; Destinations = @( ... ) }")
			$aiHarnesses = $null
		}
		else {
			foreach ($harnessName in $aiHarnesses.Keys) {
				$harness = $aiHarnesses[$harnessName]
				if (-not ($harness -is [System.Collections.IDictionary])) {
					$failures.Add("AiHarnesses.$harnessName must be a hashtable with Destinations = @( ... )")
					continue
				}
				$index = 0
				foreach ($destination in @($harness['Destinations'])) {
					$index++
					if ($null -eq $destination) { continue }
					if (-not ($destination -is [System.Collections.IDictionary])) {
						$failures.Add("AiHarnesses.$harnessName.Destinations[$index] must be a hashtable")
						continue
					}
					if ($aiKinds -notcontains ([string]$destination['Kind']).ToLowerInvariant()) {
						$failures.Add("AiHarnesses.$harnessName.Destinations[$index] has Kind [$($destination['Kind'])] - expected Skills, Mods, Rules, Prompts or Agents")
					}
					if (@('each', 'copy', 'file') -notcontains ([string]$destination['Placement']).ToLowerInvariant()) {
						$failures.Add("AiHarnesses.$harnessName.Destinations[$index] has Placement [$($destination['Placement'])] - expected Each, Copy or File")
					}
					if (@($destination['Files'] | Where-Object { $_ }).Count -eq 0 -or -not $destination['Path']) {
						$failures.Add("AiHarnesses.$harnessName.Destinations[$index] needs Files and Path")
					}
				}
			}
		}
	}

	$aiArtifacts = $Configuration['AiArtifacts']
	if ($null -ne $aiArtifacts) {
		if (-not ($aiArtifacts -is [System.Collections.IDictionary])) {
			$failures.Add("AiArtifacts must be a hashtable (Root, Sources, Exclude, Use, Deploy)")
		}
		else {
			$deploy = $aiArtifacts['Deploy']
			if ($null -ne $deploy -and -not ($deploy -is [System.Collections.IDictionary])) {
				$failures.Add("AiArtifacts.Deploy must be a hashtable of machine type => harness names, e.g. @{ Default = @(`"claude-code`") }")
			}
			elseif ($null -ne $deploy -and $null -ne $aiHarnesses) {
				foreach ($machine in $deploy.Keys) {
					foreach ($harnessName in @($deploy[$machine] | Where-Object { $_ })) {
						if (@($aiHarnesses.Keys | Where-Object { [string]$_ -eq [string]$harnessName }).Count -eq 0) {
							$failures.Add("AiArtifacts.Deploy.$machine names [$harnessName], which is no AiHarnesses entry")
						}
					}
				}
			}
			$use = $aiArtifacts['Use']
			if ($use -is [System.Collections.IDictionary]) {
				foreach ($kind in $use.Keys) {
					if ($aiKinds -notcontains ([string]$kind).ToLowerInvariant()) {
						$failures.Add("AiArtifacts.Use has the key [$kind] - expected Skills, Mods, Rules, Prompts or Agents")
					}
				}
			}
			foreach ($entry in @($aiArtifacts['Exclude'])) {
				$item = if ($entry -is [System.Collections.IDictionary]) { [string]$entry['Item'] } else { [string]$entry }
				if (-not $item) { continue }
				$parts = $item.Split('/')
				if ($parts.Count -lt 2 -or $parts.Count -gt 3 -or $aiKinds -notcontains $parts[0].ToLowerInvariant() -or @($parts | Where-Object { -not $_ }).Count -gt 0) {
					$failures.Add("AiArtifacts.Exclude has [$item] - expected KIND/NAME or KIND/SOURCE/NAME, e.g. skills/tdd")
				}
			}
		}
	}

	# Deprecated keys and step names: one warning each, never a failure.
	$deprecationWarnings = [System.Collections.Generic.List[string]]::new()
	foreach ($deprecation in $deprecations) {
		$segments = $deprecation.Path.Split('.')
		$parent = $Configuration
		foreach ($segment in $segments[0..($segments.Count - 2)]) {
			if ($parent -is [System.Collections.IDictionary] -and $parent.Contains($segment)) { $parent = $parent[$segment] } else { $parent = $null; break }
		}
		if (-not ($parent -is [System.Collections.IDictionary]) -or -not $parent.Contains($segments[-1])) { continue }
		$value = $parent[$segments[-1]]
		$inUse = switch ($deprecation.When) {
			'Present' { $true }
			'NotEmpty' { [bool](Test-ConfigValue $value) }
			'NotDefault' { (@($value | ForEach-Object { ([string]$_).TrimEnd('\') }) -join '|') -ne (@($deprecation.Default | ForEach-Object { ([string]$_).TrimEnd('\') }) -join '|') }
		}
		if ($inUse) {
			$deprecationWarnings.Add("$($deprecation.Path) is deprecated since $($deprecation.Since) and removed in $($deprecation.Removal) - use $($deprecation.Replacement)")
		}
	}
	if ($deprecationWarnings.Count -gt 0) {
		Write-Warning ("Configuration uses $($deprecationWarnings.Count) deprecated key(s) (see CHANGELOG.md, ### Deprecated):`n  - " + ($deprecationWarnings -join "`n  - "))
	}

	if ($failures.Count -gt 0) {
		$summary = "Configuration schema validation found $($failures.Count) issue(s):"
		$detail = $failures -join "`n  - "
		$message = "$summary`n  - $detail`n`nVerify Configuration.psd1 and that Load-PathConfiguration completed successfully."

		if ($Strict) {
			throw $message
		}
		else {
			Write-Warning $message
		}
	}
	else {
		Write-Verbose "Configuration schema validation passed - all required keys present."
	}
}

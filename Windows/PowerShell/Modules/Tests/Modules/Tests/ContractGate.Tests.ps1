#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	foreach ($helper in 'Get-ChangelogReleases', 'Get-ContractSnapshot', 'New-ContractBaseline', 'Test-ContractCompatibility', 'Test-ChangelogVersionBumps') {
		. (Join-Path $ModuleRoot "Tests\$helper.ps1")
	}

	# A miniature repository: two modules (one exporting an alias), the fork-owned Custom area that
	# must be ignored, and a shipped configuration with nested keys. Nothing here is ever run.
	$script:Repo = Join-Path $TestDrive 'repo'
	$script:Modules = Join-Path $script:Repo 'Windows\PowerShell\Modules'
	$script:Configuration = Join-Path $script:Repo 'Windows\PowerShell\Configuration.psd1'
	$files = [ordered]@{
		'Windows\PowerShell\Configuration.psd1'                     = '@{ GitConfig = @{ UserName = ""; UserEmail = "" }; DefaultLocale = "en-US"; PathTemplates = @{ Old = ""; Projects = @{ Self = @{ Root = "" } } } }'
		'Windows\PowerShell\Modules\Alpha\Alpha.psd1'               = "@{ FunctionsToExport = @('Get-Thing', 'Set-Thing'); AliasesToExport = @('gt') }"
		'Windows\PowerShell\Modules\Alpha\Functions\Get-Thing.ps1'  = "function Get-Thing {`n`tparam(`n`t`t[Parameter(Mandatory = `$true)][string]`$Name,`n`t`t[Alias('Max')][int]`$Limit = 5,`n`t`t[switch]`$Force`n`t)`n}"
		'Windows\PowerShell\Modules\Alpha\Functions\Set-Thing.ps1'  = 'function Set-Thing($Value) { }'
		'Windows\PowerShell\Modules\Beta\Beta.psd1'                 = "@{ FunctionsToExport = @('Invoke-Beta') }"
		'Windows\PowerShell\Modules\Beta\Functions\Invoke-Beta.ps1' = "function Invoke-Beta {`n`t[CmdletBinding()]`n`tparam([Parameter(Mandatory)][string]`$Target)`n}"
		'Windows\PowerShell\Modules\Custom\Custom.psd1'             = "@{ FunctionsToExport = @('Fork-Only') }"
	}
	foreach ($relative in $files.Keys) {
		$full = Join-Path $script:Repo $relative
		New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
		Set-Content -LiteralPath $full -Value $files[$relative]
	}

	# Turns a snapshot or baseline into what ContractBaseline.json reads back as.
	function ConvertTo-StoredBaseline {
		param([System.Collections.IDictionary]$Baseline)
		$Baseline | ConvertTo-Json -Depth 8 | ConvertFrom-Json
	}
}

Describe "Get-ChangelogReleases" {
	It "splits [Unreleased] and the releases, newest first, with their subsections" {
		$text = @"
# Changelog

## [Unreleased]

### Removed

- ``Old-Thing``

## [2.0.0-rc.1] - 2027-01-01

### Breaking

- big

## [1.1.0] - 2026-12-01

### Added

- new

### Fixed

- bug

[Unreleased]: https://example.invalid/compare
[1.1.0]: https://example.invalid/compare/v1.0.0...v1.1.0
"@
		$parsed = Get-ChangelogReleases -Text $text

		$parsed.Unreleased.Keys | Should -Be @('Removed')
		$parsed.Unreleased.Removed | Should -Match '`Old-Thing`'
		$parsed.Releases.Version | Should -Be @('2.0.0-rc.1', '1.1.0')
		$parsed.Releases[0].Major | Should -Be 2
		$parsed.Releases[0].Patch | Should -Be 0
		($parsed.Releases[1].Sections.Keys | Sort-Object) | Should -Be @('Added', 'Fixed')
		$parsed.Releases[1].Sections.Fixed | Should -Not -Match 'example.invalid'
	}

	It "returns no releases and an empty [Unreleased] for a changelog without them" {
		$parsed = Get-ChangelogReleases -Text "# Changelog`n"

		@($parsed.Releases).Count | Should -Be 0
		$parsed.Unreleased.Count | Should -Be 0
	}
}

Describe "Get-ContractSnapshot" {
	BeforeAll {
		$script:snapshot = Get-ContractSnapshot -ModulesRoot $script:Modules -ConfigurationPath $script:Configuration
	}

	It "lists every exported function of every module except the Custom area, sorted" {
		@($script:snapshot.Functions.Keys) | Should -Be @('Get-Thing', 'Invoke-Beta', 'Set-Thing')
		$script:snapshot.Functions['Get-Thing'].Module | Should -Be 'Alpha'
	}

	It "reads each parameter's mandatory flag and aliases from the syntax tree" {
		$parameters = $script:snapshot.Functions['Get-Thing'].Parameters

		@($parameters.Keys) | Should -Be @('Force', 'Limit', 'Name')
		$parameters['Name'].Mandatory | Should -BeTrue
		$parameters['Limit'].Mandatory | Should -BeFalse
		@($parameters['Limit'].Aliases) | Should -Be @('Max')
	}

	It "reads a bare Mandatory attribute and a function written without a param block" {
		$script:snapshot.Functions['Invoke-Beta'].Parameters['Target'].Mandatory | Should -BeTrue
		@($script:snapshot.Functions['Set-Thing'].Parameters.Keys) | Should -Be @('Value')
	}

	It "lists the exported aliases" {
		@($script:snapshot.Aliases) | Should -Be @('gt')
	}

	It "lists configuration keys two levels deep, not deeper" {
		@($script:snapshot.ConfigurationKeys) | Should -Be @('DefaultLocale', 'GitConfig', 'GitConfig.UserEmail', 'GitConfig.UserName', 'PathTemplates', 'PathTemplates.Old', 'PathTemplates.Projects')
	}
}

Describe "Test-ContractCompatibility" {
	BeforeEach {
		$script:baseline = ConvertTo-StoredBaseline (New-ContractBaseline -Snapshot (Get-ContractSnapshot -ModulesRoot $script:Modules -ConfigurationPath $script:Configuration) -Version '1.0.0' -Previous $null)
		$script:baseline.Deprecated.ConfigurationKeys | Add-Member -NotePropertyName 'PathTemplates.Old' -NotePropertyValue '1.0.0'
		$script:current = Get-ContractSnapshot -ModulesRoot $script:Modules -ConfigurationPath $script:Configuration
	}

	It "reports nothing for an unchanged contract" {
		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{}) | Should -BeNullOrEmpty
	}

	It "reports nothing for additions: a new function, an optional parameter, a new key" {
		$script:current.Functions['New-Thing'] = [ordered]@{ Module = 'Alpha'; Parameters = [ordered]@{} }
		$script:current.Functions['Get-Thing'].Parameters['Extra'] = [ordered]@{ Mandatory = $false; Aliases = @() }
		$script:current.ConfigurationKeys = @($script:current.ConfigurationKeys) + 'NewKey'

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{}) | Should -BeNullOrEmpty
	}

	It "reports a removed function, a removed parameter, a removed key and a newly mandatory parameter" {
		$script:current.Functions.Remove('Set-Thing')
		$script:current.Functions['Get-Thing'].Parameters.Remove('Force')
		$script:current.Functions['Get-Thing'].Parameters['Limit'].Mandatory = $true
		$script:current.ConfigurationKeys = @($script:current.ConfigurationKeys | Where-Object { $_ -ne 'GitConfig.UserEmail' })

		$violations = @(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{})

		$violations.Count | Should -Be 4
		($violations -join "`n") | Should -Match '\[Set-Thing\] was removed'
		($violations -join "`n") | Should -Match '\[-Force\] of \[Get-Thing\] was removed'
		($violations -join "`n") | Should -Match '\[-Limit\] of \[Get-Thing\] is mandatory now'
		($violations -join "`n") | Should -Match '\[GitConfig.UserEmail\]'
	}

	It "accepts a parameter renamed with the old name kept as an [Alias()]" {
		$script:current.Functions['Get-Thing'].Parameters.Remove('Force')
		$script:current.Functions['Get-Thing'].Parameters['Overwrite'] = [ordered]@{ Mandatory = $false; Aliases = @('Force') }

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{}) | Should -BeNullOrEmpty
	}

	It "accepts a function kept as an exported alias" {
		$script:current.Functions.Remove('Set-Thing')
		$script:current.Aliases = @('gt', 'Set-Thing')

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{}) | Should -BeNullOrEmpty
	}

	It "accepts removing an item deprecated in a shipped release when [Unreleased] lists it under Removed" {
		$script:current.ConfigurationKeys = @($script:current.ConfigurationKeys | Where-Object { $_ -ne 'PathTemplates.Old' })

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{ Removed = '- `PathTemplates.Old` is gone.' }) | Should -BeNullOrEmpty
	}

	It "still reports that removal when [Unreleased] does not list it" {
		$script:current.ConfigurationKeys = @($script:current.ConfigurationKeys | Where-Object { $_ -ne 'PathTemplates.Old' })

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{}).Count | Should -Be 1
	}

	It "reports removing an item that was never deprecated, even when [Unreleased] lists it under Removed" {
		$script:current.Functions.Remove('Set-Thing')

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{ Removed = '`Set-Thing`' }).Count | Should -Be 1
	}

	It "reports removing an item whose deprecation has not shipped yet" {
		$script:baseline.Deprecated.Functions | Add-Member -NotePropertyName 'Set-Thing' -NotePropertyValue '1.1.0'
		$script:current.Functions.Remove('Set-Thing')

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{ Removed = '`Set-Thing`' }).Count | Should -Be 1
	}

	It "accepts an immediate break that [Unreleased] lists under Breaking" {
		$script:current.Functions.Remove('Set-Thing')
		$script:current.Functions['Get-Thing'].Parameters['Limit'].Mandatory = $true

		@(Test-ContractCompatibility -Baseline $script:baseline -Current $script:current -Unreleased @{ Breaking = '`Set-Thing` and `Get-Thing -Limit`' }) | Should -BeNullOrEmpty
	}
}

Describe "New-ContractBaseline" {
	BeforeAll {
		$script:snapshot = Get-ContractSnapshot -ModulesRoot $script:Modules -ConfigurationPath $script:Configuration
	}

	It "stamps the snapshot with the release version and starts with no deprecation records" {
		$baseline = New-ContractBaseline -Snapshot $script:snapshot -Version '1.0.0' -Previous $null

		$baseline.Version | Should -Be '1.0.0'
		@($baseline.Functions.Keys) | Should -Be @('Get-Thing', 'Invoke-Beta', 'Set-Thing')
		$baseline.Deprecated.ConfigurationKeys.Count | Should -Be 0
	}

	It "keeps records for items still present and items the snapshot never saw, and drops removed ones" {
		$previous = ConvertTo-StoredBaseline (New-ContractBaseline -Snapshot $script:snapshot -Version '1.0.0' -Previous $null)
		$previous.Functions | Add-Member -NotePropertyName 'Old-Function' -NotePropertyValue ([pscustomobject]@{ Module = 'Alpha'; Parameters = [pscustomobject]@{} })
		$previous.Deprecated.Functions | Add-Member -NotePropertyName 'Old-Function' -NotePropertyValue '0.9.0'
		$previous.Deprecated.ConfigurationKeys | Add-Member -NotePropertyName 'PathTemplates.Old' -NotePropertyValue '1.0.0'
		$previous.Deprecated.ConfigurationKeys | Add-Member -NotePropertyName 'BootstrapConfig.Legacy' -NotePropertyValue '0.5.0'
		$previous.Deprecated.Parameters | Add-Member -NotePropertyName 'Get-Thing -Force' -NotePropertyValue '1.0.0'

		$baseline = New-ContractBaseline -Snapshot $script:snapshot -Version '2.0.0' -Previous $previous

		$baseline.Deprecated.Functions.Contains('Old-Function') | Should -BeFalse
		$baseline.Deprecated.ConfigurationKeys['PathTemplates.Old'] | Should -Be '1.0.0'
		$baseline.Deprecated.ConfigurationKeys['BootstrapConfig.Legacy'] | Should -Be '0.5.0'
		$baseline.Deprecated.Parameters['Get-Thing -Force'] | Should -Be '1.0.0'
	}
}

Describe "Test-ChangelogVersionBumps" {
	BeforeAll {
		function New-Release {
			param([string]$Version, [string[]]$Sections)
			$parts = $Version -split '\.'
			$table = @{}
			foreach ($section in $Sections) { $table[$section] = "- entry" }
			[pscustomobject]@{ Version = $Version; Major = [int]$parts[0]; Minor = [int]$parts[1]; Patch = [int]$parts[2]; Sections = $table }
		}
	}

	It "accepts a PATCH of fixes, a MINOR of additions and changes, and a MAJOR of removals" {
		$releases = @(
			(New-Release '2.0.0' 'Removed', 'Added')
			(New-Release '1.2.0' 'Added', 'Deprecated')
			(New-Release '1.1.1' 'Fixed', 'Security')
			(New-Release '1.1.0' 'Added')
			(New-Release '1.0.0' 'Changed')
		)

		@(Test-ChangelogVersionBumps -Releases $releases) | Should -BeNullOrEmpty
	}

	It "rejects a removal or a break that is not a MAJOR" {
		$violations = @(Test-ChangelogVersionBumps -Releases @((New-Release '1.1.0' 'Breaking'), (New-Release '1.0.0' 'Changed')))

		$violations.Count | Should -Be 1
		$violations[0] | Should -Match 'must be a MAJOR'
	}

	It "rejects a MAJOR that removes and breaks nothing" {
		$violations = @(Test-ChangelogVersionBumps -Releases @((New-Release '2.0.0' 'Added', 'Changed'), (New-Release '1.4.0' 'Added')))

		$violations.Count | Should -Be 1
		$violations[0] | Should -Match 'removes and breaks nothing'
	}

	It "rejects an addition, a change or a deprecation in a PATCH" {
		foreach ($kind in 'Added', 'Changed', 'Deprecated') {
			$violations = @(Test-ChangelogVersionBumps -Releases @((New-Release '1.0.1' $kind), (New-Release '1.0.0' 'Changed')))

			$violations.Count | Should -Be 1 -Because "a [$kind] section is at least a MINOR"
			$violations[0] | Should -Match 'at least a MINOR'
		}
	}

	It "rejects a version that does not reset the lower parts, and one that does not go up" {
		(@(Test-ChangelogVersionBumps -Releases @((New-Release '2.1.0' 'Removed'), (New-Release '1.3.0' 'Added'))) -join "`n") | Should -Match 'MINOR and PATCH must be 0'
		(@(Test-ChangelogVersionBumps -Releases @((New-Release '1.2.3' 'Added'), (New-Release '1.1.0' 'Added'))) -join "`n") | Should -Match 'PATCH must be 0'
		(@(Test-ChangelogVersionBumps -Releases @((New-Release '1.1.0' 'Fixed'), (New-Release '1.1.0' 'Fixed'))) -join "`n") | Should -Match 'not higher'
	}

	It "exempts the 0.x series and the step from it to 1.0.0" {
		$releases = @(
			(New-Release '1.0.0' 'Added', 'Changed')
			(New-Release '0.1.94' 'Breaking')
			(New-Release '0.1.93' 'Added')
		)

		@(Test-ChangelogVersionBumps -Releases $releases) | Should -BeNullOrEmpty
	}
}

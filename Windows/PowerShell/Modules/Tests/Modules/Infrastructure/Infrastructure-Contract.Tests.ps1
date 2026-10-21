#Requires -Modules Pester

Describe "Contract" {
	<#
	.SYNOPSIS
		Enforces VERSIONING.md: the contract a fork depends on only breaks in a MAJOR, only after a
		deprecation, and a version bump says what the release changed.

	.DESCRIPTION
		Modules/Tests/ContractBaseline.json records the contract at the last release - every
		exported function with its parameters, and the shipped Configuration.psd1's keys two levels
		deep - plus the Deprecated records. This gate fails a change that:

		- removes an exported function, a parameter or a configuration key, or makes a parameter
		  mandatory, unless [Unreleased] in CHANGELOG.md sanctions it: a "### Removed" entry naming
		  an item deprecated in an earlier release, a "### Breaking" entry, or a "### Withdrawn" entry
		  for an item that was never meant to be shared engine code (Test-ContractCompatibility);
		- releases a version whose bump does not match its changelog section - a removal outside a
		  MAJOR, a MAJOR that removes nothing, an addition in a PATCH (Test-ChangelogVersionBumps);
		- releases without refreshing the baseline (Run-Tests -UpdateContractBaseline).
	#>

	BeforeAll {
		$TestsRoot = Join-Path (Get-RepositoryPath).Modules "Tests"
		foreach ($helper in 'Get-ChangelogReleases', 'Get-ContractSnapshot', 'Test-ContractCompatibility', 'Test-ChangelogVersionBumps') {
			. (Join-Path $TestsRoot "$helper.ps1")
		}

		$RepoPaths = Get-RepositoryPath
		$BaselineFile = Join-Path $TestsRoot "ContractBaseline.json"
		$Changelog = Get-ChangelogReleases -Path (Join-Path $RepoPaths.Repo "CHANGELOG.md")
		$Baseline = if (Test-Path -LiteralPath $BaselineFile) { Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json } else { $null }
	}

	It "has a committed contract baseline" {
		$BaselineFile | Should -Exist -Because "the baseline is what every change is held to; create it with Run-Tests -UpdateContractBaseline"
	}

	It "has a baseline taken at the newest release in CHANGELOG.md" {
		$Baseline.Version | Should -Be $Changelog.Releases[0].Version -Because "every release refreshes the baseline in its release commit: Run-Tests -UpdateContractBaseline"
	}

	It "keeps every deprecation record's version a released version" {
		foreach ($kind in 'Functions', 'Parameters', 'ConfigurationKeys') {
			foreach ($record in @($Baseline.Deprecated.$kind.PSObject.Properties)) {
				[string]$record.Value | Should -Match '^\d+\.\d+\.\d+$' -Because "Deprecated.$kind.$($record.Name) records the version its deprecation ships in"
			}
		}
	}

	It "breaks no part of the contract outside a sanctioned removal" {
		$current = Get-ContractSnapshot -ModulesRoot $RepoPaths.Modules -ConfigurationPath (Join-Path $RepoPaths.PowerShell "Configuration.psd1")

		$violations = @(Test-ContractCompatibility -Baseline $Baseline -Current $current -Unreleased $Changelog.Unreleased)

		$violations | Should -BeNullOrEmpty -Because "VERSIONING.md: deprecate first, remove in the next MAJOR. Violations:`n$($violations -join "`n")"
	}

	It "bumps every release since 1.0.0 the way its changelog section requires" {
		$violations = @(Test-ChangelogVersionBumps -Releases $Changelog.Releases)

		$violations | Should -BeNullOrEmpty -Because "VERSIONING.md's bump table. Violations:`n$($violations -join "`n")"
	}
}

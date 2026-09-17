#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-OrderedNames.ps1"
	. "$HelperFunctionsPath\Get-OrderedEntry.ps1"

	# The shape every menu-bearing configuration section has: one single-key hashtable per
	# entry, in the order the menu offers them. Deliberately NOT alphabetical, so a test that
	# passes only because the names happen to sort that way cannot hide here.
	$script:OrderedSection = @(
		@{ Zulu = @{ Value = 1 } }
		@{ Alpha = @{ Value = 2 } }
		@{ "Proxmox Backup Server" = @{ Value = 3 } }
	)
}

Describe "Get-OrderedNames" {
	It "returns the entry names in configuration order, not sorted" {
		@(Get-OrderedNames $script:OrderedSection) | Should -Be @('Zulu', 'Alpha', 'Proxmox Backup Server')
	}

	It "returns nothing for an unconfigured section" {
		@(Get-OrderedNames $null).Count | Should -Be 0
		@(Get-OrderedNames @()).Count | Should -Be 0
	}

	It "sorts the keys of a section still written as a hashtable" {
		# Import-PowerShellDataFile loses key order, so sorted is the only stable answer -
		# and Test-ConfigurationSchema is what tells the fork to migrate.
		@(Get-OrderedNames @{ Zulu = 1; Alpha = 2 }) | Should -Be @('Alpha', 'Zulu')
	}

	It "takes a bare string entry as naming itself" {
		@(Get-OrderedNames @('First', 'Second')) | Should -Be @('First', 'Second')
	}
}

Describe "Get-OrderedEntry" {
	It "looks an entry up by name" {
		(Get-OrderedEntry $script:OrderedSection 'Alpha').Value | Should -Be 2
	}

	It "matches a name with spaces" {
		(Get-OrderedEntry $script:OrderedSection 'Proxmox Backup Server').Value | Should -Be 3
	}

	It "matches case-insensitively, the way the menus do" {
		(Get-OrderedEntry $script:OrderedSection 'zULU').Value | Should -Be 1
	}

	It "returns null for a name that is not configured" {
		Get-OrderedEntry $script:OrderedSection 'Missing' | Should -BeNullOrEmpty
	}

	It "returns null for an unconfigured section" {
		Get-OrderedEntry $null 'Alpha' | Should -BeNullOrEmpty
		Get-OrderedEntry @() 'Alpha' | Should -BeNullOrEmpty
	}

	It "reads a section still written as a hashtable" {
		(Get-OrderedEntry @{ Alpha = @{ Value = 9 } } 'Alpha').Value | Should -Be 9
	}

	It "takes the first of two entries with the same name, the way the file reads" {
		$duplicated = @(
			@{ Alpha = @{ Value = 'first' } }
			@{ Alpha = @{ Value = 'second' } }
		)

		(Get-OrderedEntry $duplicated 'Alpha').Value | Should -Be 'first'
	}
}

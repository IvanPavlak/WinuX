#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "System\Functions"
	. "$FunctionsPath\Resolve-VisibleWindowExclusions.ps1"
	# The scope gate is a Bootstrap sibling; loaded here so the Write-LogError mock reaches it.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")

	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Resolve-VisibleWindowExclusions" {
	BeforeEach {
		Mock Write-LogError { }
		$global:Configuration = @{
			ValidMachineTypes = @("PC", "Laptop", "Work")
			Universal         = @{
				VisibleWindowExclusions = @(
					"Rainmeter"
					@{ Name = "MyAgentApp"; Machine = "PC" }
					@{ Name = "MyMeetingApp"; Machine = "Laptop/Work" }
					@{ Name = "MyEverywhereApp" }
				)
			}
		}
	}

	It "keeps plain names everywhere and scoped names only on their machine types" {
		@(Resolve-VisibleWindowExclusions -MachineType "PC") | Should -Be @("Rainmeter", "MyAgentApp", "MyEverywhereApp")
		@(Resolve-VisibleWindowExclusions -MachineType "Work") | Should -Be @("Rainmeter", "MyMeetingApp", "MyEverywhereApp")
	}

	It "never applies an entry whose scope names an unknown machine type, and reports it" {
		$global:Configuration.Universal.VisibleWindowExclusions = @(@{ Name = "MyAgentApp"; Machine = "Labtop" })

		@(Resolve-VisibleWindowExclusions -MachineType "Laptop") | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "skips entries without a name and collapses duplicates case-insensitively" {
		$global:Configuration.Universal.VisibleWindowExclusions = @("Rainmeter", "", @{ Machine = "PC" }, "rainmeter", $null)

		@(Resolve-VisibleWindowExclusions -MachineType "PC") | Should -Be @("Rainmeter")
	}

	It "returns nothing when the key is absent" {
		$global:Configuration = @{ Universal = @{} }

		@(Resolve-VisibleWindowExclusions -MachineType "PC") | Should -BeNullOrEmpty
	}
}

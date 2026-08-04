#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
}

AfterAll {
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-Steps" {
	BeforeEach {
		$global:MachineType = "Test"

		Mock Write-LogWarning { }

		$script:Defaults = [ordered]@{
			First  = $true
			Second = $true
			OptIn  = $false
		}
	}

	Context "Defaults" {
		It "Should return the built-in defaults when no config is given" {
			$states = Resolve-Steps -Defaults $script:Defaults

			$states["First"] | Should -BeTrue
			$states["Second"] | Should -BeTrue
			$states["OptIn"] | Should -BeFalse
		}

		It "Should preserve the order the defaults dictionary defines" {
			$states = Resolve-Steps -Defaults $script:Defaults

			@($states.Keys) -join "," | Should -Be "First,Second,OptIn"
		}

		It "Should return the default for steps absent from a partial config" {
			$states = Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = $false }

			$states["First"] | Should -BeFalse
			$states["Second"] | Should -BeTrue
		}

		It "Should ignore config keys that are not in the defaults" {
			$states = Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ Unknown = $false }

			@($states.Keys) | Should -Not -Contain "Unknown"
		}
	}

	Context "Parameter overrides" {
		It "Should force a step off with Skip" {
			$states = Resolve-Steps -Defaults $script:Defaults -Skip @("First")

			$states["First"] | Should -BeFalse
			$states["Second"] | Should -BeTrue
		}

		It "Should force a config-disabled step on with Include" {
			$states = Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = $false } -Include @("First")

			$states["First"] | Should -BeTrue
		}

		It "Should let Skip win over Include and warn once per conflicting step" {
			$states = Resolve-Steps -Defaults $script:Defaults -Skip @("First") -Include @("First")

			$states["First"] | Should -BeFalse
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "First" }
		}

		It "Should not warn when Skip does not collide with Include" {
			$states = Resolve-Steps -Defaults $script:Defaults -Skip @("First") -Include @("Second")

			$states["First"] | Should -BeFalse
			$states["Second"] | Should -BeTrue
			Should -Invoke Write-LogWarning -Times 0
		}
	}

	Context "Config resolution" {
		It "Should use a plain boolean config value" {
			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = $false })["First"] | Should -BeFalse
		}

		It "Should treat an explicit config true as real for an off-by-default step" {
			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ OptIn = $true })["OptIn"] | Should -BeTrue
		}

		It "Should use the machine type key of a hashtable value" {
			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = @{ Default = $true; Test = $false } })["First"] | Should -BeFalse
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"

			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = @{ Default = $false; Test = $true } })["First"] | Should -BeFalse
		}

		It "Should fall back to the built-in default when neither the machine type nor Default is mapped" {
			$global:MachineType = "Laptop"

			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = @{ Test = $false } })["First"] | Should -BeTrue
		}

		It "Should not index the hashtable with a null machine type" {
			$global:MachineType = $null

			(Resolve-Steps -Defaults $script:Defaults -ConfigSteps @{ First = @{ Default = $false } })["First"] | Should -BeFalse
		}
	}
}

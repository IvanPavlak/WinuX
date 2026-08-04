#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Resolve-KillAllStep.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-KillAllStep" {
	BeforeEach {
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-LogWarning { }
	}

	Context "Parameter overrides" {
		It "Should return false when the step is in Skip" {
			Resolve-KillAllStep -Name "Docker" -Default $true -Skip @("Docker") | Should -BeFalse
		}

		It "Should return true when the step is in Include and config disables it" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			Resolve-KillAllStep -Name "Docker" -Default $true -Include @("Docker") | Should -BeTrue
		}

		It "Should let Skip win over Include and warn" {
			Resolve-KillAllStep -Name "Docker" -Default $true -Skip @("Docker") -Include @("Docker") | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "Docker" }
		}

		It "Should not warn when Skip does not collide with Include" {
			Resolve-KillAllStep -Name "Docker" -Default $true -Skip @("Docker") -Include @("Browsers") | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 0
		}
	}

	Context "Config resolution" {
		It "Should use a plain boolean config value" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeFalse
		}

		It "Should treat an explicit config false as real (not truthiness)" {
			$global:Configuration.KillAll = @{ Steps = @{ ReloadProfile = $false } }

			Resolve-KillAllStep -Name "ReloadProfile" -Default $false | Should -BeFalse
		}

		It "Should use the machine type key of a hashtable value" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $true; Test = $false } } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeFalse
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $false; Test = $true } } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeFalse
		}

		It "Should fall back to the built-in default when neither the machine type nor Default is mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Test = $false } } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeTrue
		}

		It "Should not index the hashtable with a null machine type" {
			$global:MachineType = $null
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $false } } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeFalse
		}
	}

	Context "Built-in defaults" {
		It "Should return the default when no config section exists" {
			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeTrue
			Resolve-KillAllStep -Name "ReloadProfile" -Default $false | Should -BeFalse
		}

		It "Should return the default when the step key is absent from Steps" {
			$global:Configuration.KillAll = @{ Steps = @{ Browsers = $false } }

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeTrue
		}

		It "Should return the default when Configuration itself is null" {
			$global:Configuration = $null

			Resolve-KillAllStep -Name "Docker" -Default $true | Should -BeTrue
		}
	}
}

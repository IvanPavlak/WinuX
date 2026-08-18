#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	# Resolve-RunProjectSteps delegates the resolution loop to the shared Resolve-Steps.
	. "$FunctionsPath\Resolve-Steps.ps1"
	. "$FunctionsPath\Resolve-RunProjectSteps.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-RunProjectSteps" {
	BeforeEach {
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-LogWarning { }
	}

	It "Should default Docker to on when nothing decides otherwise" {
		(Resolve-RunProjectSteps)["Docker"] | Should -BeTrue
	}

	It "Should return the defaults when Configuration itself is null" {
		$global:Configuration = $null

		(Resolve-RunProjectSteps)["Docker"] | Should -BeTrue
	}

	It "Should use a plain boolean config value" {
		$global:Configuration.RunProject = @{ Steps = @{ Docker = $false } }

		(Resolve-RunProjectSteps)["Docker"] | Should -BeFalse
	}

	It "Should use the machine type key of a hashtable value" {
		$global:Configuration.RunProject = @{ Steps = @{ Docker = @{ Default = $true; Test = $false } } }

		(Resolve-RunProjectSteps)["Docker"] | Should -BeFalse
	}

	It "Should fall back to Default when the machine type is not mapped" {
		$global:MachineType = "Laptop"
		$global:Configuration.RunProject = @{ Steps = @{ Docker = @{ Default = $false; Test = $true } } }

		(Resolve-RunProjectSteps)["Docker"] | Should -BeFalse
	}

	It "Should force a step off with Skip" {
		(Resolve-RunProjectSteps -Skip @("Docker"))["Docker"] | Should -BeFalse
	}

	It "Should force a config-disabled step on with Include" {
		$global:Configuration.RunProject = @{ Steps = @{ Docker = $false } }

		(Resolve-RunProjectSteps -Include @("Docker"))["Docker"] | Should -BeTrue
	}

	It "Should let Skip win over Include and warn once" {
		$states = Resolve-RunProjectSteps -Skip @("Docker") -Include @("Docker")

		$states["Docker"] | Should -BeFalse
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "Docker" }
	}
}

#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Resolve-KillAllSteps.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-KillAllSteps" {
	BeforeEach {
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-LogWarning { }
	}

	Context "Built-in defaults" {
		It "Should return every step on except ReloadProfile when nothing decides otherwise" {
			$states = Resolve-KillAllSteps

			foreach ($name in @("VirtualDesktops", "Docker", "Browsers", "VisibleWindows", "NamedProcesses", "TerminalTabs", "CenterTerminal", "FocusTerminal")) {
				$states[$name] | Should -BeTrue -Because "step [$name] defaults to on"
			}
			$states["ReloadProfile"] | Should -BeFalse
		}

		It "Should list the steps in Kill-All execution order" {
			$states = Resolve-KillAllSteps

			@($states.Keys) -join "," | Should -Be "VirtualDesktops,Docker,Browsers,VisibleWindows,NamedProcesses,TerminalTabs,CenterTerminal,FocusTerminal,ReloadProfile"
		}

		It "Should return the defaults when Configuration itself is null" {
			$global:Configuration = $null

			$states = Resolve-KillAllSteps

			$states["Docker"] | Should -BeTrue
		}

		It "Should return the default for steps absent from a partial Steps section" {
			$global:Configuration.KillAll = @{ Steps = @{ Browsers = $false } }

			$states = Resolve-KillAllSteps

			$states["Browsers"] | Should -BeFalse
			$states["Docker"] | Should -BeTrue
		}
	}

	Context "Parameter overrides" {
		It "Should force a step off with Skip" {
			$states = Resolve-KillAllSteps -Skip @("Docker")

			$states["Docker"] | Should -BeFalse
			$states["Browsers"] | Should -BeTrue
		}

		It "Should force a config-disabled step on with Include" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			$states = Resolve-KillAllSteps -Include @("Docker")

			$states["Docker"] | Should -BeTrue
		}

		It "Should let Skip win over Include and warn once per conflicting step" {
			$states = Resolve-KillAllSteps -Skip @("Docker") -Include @("Docker")

			$states["Docker"] | Should -BeFalse
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "Docker" }
		}

		It "Should not warn when Skip does not collide with Include" {
			$states = Resolve-KillAllSteps -Skip @("Docker") -Include @("Browsers")

			$states["Docker"] | Should -BeFalse
			$states["Browsers"] | Should -BeTrue
			Should -Invoke Write-LogWarning -Times 0
		}
	}

	Context "Config resolution" {
		It "Should use a plain boolean config value" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = $false } }

			(Resolve-KillAllSteps)["Docker"] | Should -BeFalse
		}

		It "Should treat an explicit config true as real for an off-by-default step" {
			$global:Configuration.KillAll = @{ Steps = @{ ReloadProfile = $true } }

			(Resolve-KillAllSteps)["ReloadProfile"] | Should -BeTrue
		}

		It "Should use the machine type key of a hashtable value" {
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $true; Test = $false } } }

			(Resolve-KillAllSteps)["Docker"] | Should -BeFalse
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $false; Test = $true } } }

			(Resolve-KillAllSteps)["Docker"] | Should -BeFalse
		}

		It "Should fall back to the built-in default when neither the machine type nor Default is mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Test = $false } } }

			(Resolve-KillAllSteps)["Docker"] | Should -BeTrue
		}

		It "Should not index the hashtable with a null machine type" {
			$global:MachineType = $null
			$global:Configuration.KillAll = @{ Steps = @{ Docker = @{ Default = $false } } }

			(Resolve-KillAllSteps)["Docker"] | Should -BeFalse
		}
	}
}

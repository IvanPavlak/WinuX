#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules

	# Resolve-BootstrapSteps delegates the resolution loop to the shared Resolve-Steps.
	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Resolve-BootstrapSteps.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-BootstrapSteps" {
	BeforeEach {
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-LogWarning { }
	}

	Context "Built-in defaults" {
		It "Should default every step on except the six opt-in steps" {
			$states = Resolve-BootstrapSteps

			foreach ($name in @(
					"RenameMachine", "ExecutionPolicy", "PowerPlan", "PowerButtonActions", "SystemTheme",
					"Locale", "DisplayLanguage", "KeyboardLayouts", "NerdFont", "PowerShellModules",
					"SpecialFolders", "WSL", "WinGetApps", "ScoopApps", "ChocolateyApps", "UpgradeAll",
					"DotnetEf", "EnvironmentVariables", "CondaEnvironments", "Taskbar", "SymbolicLinks")) {
				$states[$name] | Should -BeTrue -Because "step [$name] defaults to on"
			}
			foreach ($name in @("MicrosoftActivationScripts", "Win11Debloat", "DeveloperMode", "NuGetConfig", "CoreAiRules", "LockedStartLayout")) {
				$states[$name] | Should -BeFalse -Because "step [$name] is opt-in"
			}
		}

		It "Should list the steps in Bootstrap execution order" {
			$states = Resolve-BootstrapSteps

			@($states.Keys) -join "," | Should -Be "RenameMachine,MicrosoftActivationScripts,Win11Debloat,ExecutionPolicy,DeveloperMode,PowerPlan,PowerButtonActions,SystemTheme,Locale,DisplayLanguage,KeyboardLayouts,NerdFont,PowerShellModules,SpecialFolders,WSL,WinGetApps,ScoopApps,ChocolateyApps,UpgradeAll,DotnetEf,EnvironmentVariables,CondaEnvironments,NuGetConfig,Taskbar,SymbolicLinks,CoreAiRules,LockedStartLayout"
		}

		It "Should return the defaults when Configuration itself is null" {
			$global:Configuration = $null

			$states = Resolve-BootstrapSteps

			$states["WSL"] | Should -BeTrue
			$states["DeveloperMode"] | Should -BeFalse
		}

		It "Should return the default for steps absent from a partial Steps section" {
			$global:Configuration.BootstrapConfig = @{ Steps = @{ UpgradeAll = $false } }

			$states = Resolve-BootstrapSteps

			$states["UpgradeAll"] | Should -BeFalse
			$states["WinGetApps"] | Should -BeTrue
		}
	}

	Context "Parameter overrides" {
		It "Should force a step off with Skip" {
			$states = Resolve-BootstrapSteps -Skip @("UpgradeAll")

			$states["UpgradeAll"] | Should -BeFalse
		}

		It "Should force an opt-in step on with Include" {
			$states = Resolve-BootstrapSteps -Include @("DeveloperMode")

			$states["DeveloperMode"] | Should -BeTrue
		}

		It "Should let Skip win over Include and warn once per conflicting step" {
			$states = Resolve-BootstrapSteps -Skip @("WSL") -Include @("WSL")

			$states["WSL"] | Should -BeFalse
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "WSL" }
		}
	}

	Context "Config resolution" {
		It "Should use a plain boolean config value" {
			$global:Configuration.BootstrapConfig = @{ Steps = @{ MicrosoftActivationScripts = $true } }

			(Resolve-BootstrapSteps)["MicrosoftActivationScripts"] | Should -BeTrue
		}

		It "Should use the machine type key of a hashtable value" {
			$global:Configuration.BootstrapConfig = @{ Steps = @{ WSL = @{ Default = $true; Test = $false } } }

			(Resolve-BootstrapSteps)["WSL"] | Should -BeFalse
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.BootstrapConfig = @{ Steps = @{ WSL = @{ Default = $false; Test = $true } } }

			(Resolve-BootstrapSteps)["WSL"] | Should -BeFalse
		}
	}

	Context "Legacy WSLSetup fallback" {
		It "Should resolve WSL from the deprecated WSLSetup when Steps has no WSL entry" {
			$global:Configuration.BootstrapConfig = @{ WSLSetup = @{ Default = $true; Test = $false } }

			(Resolve-BootstrapSteps)["WSL"] | Should -BeFalse
		}

		It "Should resolve WSL from WSLSetup when Steps exists but carries no WSL entry" {
			$global:Configuration.BootstrapConfig = @{
				Steps    = @{ UpgradeAll = $false }
				WSLSetup = @{ Default = $false }
			}

			$states = Resolve-BootstrapSteps

			$states["WSL"] | Should -BeFalse
			$states["UpgradeAll"] | Should -BeFalse
		}

		It "Should let Steps.WSL win over the deprecated WSLSetup" {
			$global:Configuration.BootstrapConfig = @{
				Steps    = @{ WSL = $true }
				WSLSetup = @{ Default = $false }
			}

			(Resolve-BootstrapSteps)["WSL"] | Should -BeTrue
		}

		It "Should not mutate the global configuration when applying the fallback" {
			$global:Configuration.BootstrapConfig = @{
				Steps    = @{ UpgradeAll = $false }
				WSLSetup = @{ Default = $false }
			}

			Resolve-BootstrapSteps | Out-Null

			$global:Configuration.BootstrapConfig.Steps.ContainsKey("WSL") | Should -BeFalse
		}
	}
}

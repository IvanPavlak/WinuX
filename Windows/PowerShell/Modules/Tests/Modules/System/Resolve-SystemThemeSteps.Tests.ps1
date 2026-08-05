#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# Resolve-SystemThemeSteps delegates the resolution loop to the shared Resolve-Steps.
	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
	. "$FunctionsPath\Resolve-SystemThemeSteps.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-SystemThemeSteps" {
	BeforeEach {
		$global:Configuration = @{}
		$global:MachineType = "Test"

		Mock Write-LogWarning { }
	}

	Context "Built-in defaults" {
		It "Should return every step on except RefreshBrowserTabs when nothing decides otherwise" {
			$states = Resolve-SystemThemeSteps

			$states["RefreshBrowserTabs"] | Should -BeFalse
			foreach ($name in @("RestartExplorer", "SetWallpaper", "SetLockScreenWallpaper")) {
				$states[$name] | Should -BeTrue -Because "step [$name] defaults to on"
			}
		}

		It "Should list the steps in Set-SystemTheme execution order" {
			$states = Resolve-SystemThemeSteps

			@($states.Keys) -join "," | Should -Be "RefreshBrowserTabs,RestartExplorer,SetWallpaper,SetLockScreenWallpaper"
		}

		It "Should return the defaults when Configuration itself is null" {
			$global:Configuration = $null

			$states = Resolve-SystemThemeSteps

			$states["SetWallpaper"] | Should -BeTrue
			$states["RefreshBrowserTabs"] | Should -BeFalse
		}

		It "Should return the default for steps absent from a partial Steps section" {
			$global:Configuration.SystemTheme = @{ Steps = @{ SetWallpaper = $false } }

			$states = Resolve-SystemThemeSteps

			$states["SetWallpaper"] | Should -BeFalse
			$states["SetLockScreenWallpaper"] | Should -BeTrue
		}
	}

	Context "Parameter overrides" {
		It "Should force a step off with Skip" {
			$states = Resolve-SystemThemeSteps -Skip @("SetWallpaper")

			$states["SetWallpaper"] | Should -BeFalse
			$states["SetLockScreenWallpaper"] | Should -BeTrue
		}

		It "Should force the off-by-default step on with Include" {
			$states = Resolve-SystemThemeSteps -Include @("RefreshBrowserTabs")

			$states["RefreshBrowserTabs"] | Should -BeTrue
		}

		It "Should let Skip win over Include and warn once per conflicting step" {
			$states = Resolve-SystemThemeSteps -Skip @("SetWallpaper") -Include @("SetWallpaper")

			$states["SetWallpaper"] | Should -BeFalse
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "SetWallpaper" }
		}

		It "Should not warn when Skip does not collide with Include" {
			$states = Resolve-SystemThemeSteps -Skip @("SetWallpaper") -Include @("RefreshBrowserTabs")

			$states["SetWallpaper"] | Should -BeFalse
			$states["RefreshBrowserTabs"] | Should -BeTrue
			Should -Invoke Write-LogWarning -Times 0
		}
	}

	Context "Config resolution" {
		It "Should use a plain boolean config value" {
			$global:Configuration.SystemTheme = @{ Steps = @{ SetLockScreenWallpaper = $false } }

			(Resolve-SystemThemeSteps)["SetLockScreenWallpaper"] | Should -BeFalse
		}

		It "Should treat an explicit config true as real for the off-by-default step" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RefreshBrowserTabs = $true } }

			(Resolve-SystemThemeSteps)["RefreshBrowserTabs"] | Should -BeTrue
		}

		# Both hashtable cases resolve AGAINST the built-in default (RestartExplorer is
		# on), so a passing assertion can only come from the config being read.
		It "Should use the machine type key of a hashtable value" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RestartExplorer = @{ Default = $true; Test = $false } } }

			(Resolve-SystemThemeSteps)["RestartExplorer"] | Should -BeFalse
		}

		It "Should fall back to Default when the machine type is not mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.SystemTheme = @{ Steps = @{ RestartExplorer = @{ Default = $false; Test = $true } } }

			(Resolve-SystemThemeSteps)["RestartExplorer"] | Should -BeFalse
		}

		It "Should fall back to the built-in default when neither the machine type nor Default is mapped" {
			$global:MachineType = "Laptop"
			$global:Configuration.SystemTheme = @{ Steps = @{ SetWallpaper = @{ Test = $false } } }

			(Resolve-SystemThemeSteps)["SetWallpaper"] | Should -BeTrue
		}

		It "Should not index the hashtable with a null machine type" {
			$global:MachineType = $null
			$global:Configuration.SystemTheme = @{ Steps = @{ SetWallpaper = @{ Default = $false } } }

			(Resolve-SystemThemeSteps)["SetWallpaper"] | Should -BeFalse
		}

		It "Should ignore a SystemTheme section that is not a hashtable" {
			$global:Configuration.SystemTheme = "Dark"

			(Resolve-SystemThemeSteps)["SetWallpaper"] | Should -BeTrue
		}
	}
}

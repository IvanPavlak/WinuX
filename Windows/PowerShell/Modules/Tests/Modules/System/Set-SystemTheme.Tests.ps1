#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	# Set-SystemTheme resolves its follow-up steps through the real
	# Resolve-SystemThemeSteps, so the gating asserted below exercises the actual
	# resolver. It delegates the resolution loop to the shared Resolve-Steps;
	# dot-source that too so the loop runs in this scope where the log mocks apply.
	. "$ModuleRoot\Helper\Functions\Resolve-Steps.ps1"
	. "$FunctionsPath\Resolve-SystemThemeSteps.ps1"

	. "$FunctionsPath\Set-SystemTheme.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Set-SystemTheme" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Themes = @{ PC = "Dark" }
		}
		# The step resolver reads $global:Configuration / $global:MachineType. Fresh
		# baseline with no SystemTheme section - built-in defaults apply (everything
		# on except RefreshBrowserTabs) unless a test opts a step out/in. Originals
		# are restored in AfterAll.
		$global:Configuration = @{}
		$global:MachineType = "PC"

		$script:previousWtSession = $env:WT_SESSION
		$env:WT_SESSION = 'test-session'

		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { "PC" }
		Mock Get-ItemProperty { [PSCustomObject]@{ AppsUseLightTheme = 0 } }
		Mock Set-ItemProperty { }
		Mock Set-Wallpaper { }
		Mock Set-LockScreenWallpaper { }
		Mock Refresh-BrowserTabs { }
		Mock Restart-Explorer { }
		Mock Terminate-WindowsTerminalTabs { }
		Mock ReRun-LastCommand { }
		Mock Write-Host { }
	}

	AfterEach {
		if ($null -ne $script:previousWtSession) {
			$env:WT_SESSION = $script:previousWtSession
		}
		else {
			Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue
		}
	}

	It "returns early when requested theme is already active" {
		{ Set-SystemTheme -Theme "Dark" } | Should -Not -Throw

		Should -Invoke Set-ItemProperty -Times 0
		Should -Invoke Set-Wallpaper -Times 1
		Should -Invoke Set-LockScreenWallpaper -Times 1
		Should -Invoke Restart-Explorer -Times 1
		Should -Invoke Terminate-WindowsTerminalTabs -Times 1 -Exactly -ParameterFilter { $OnlyCurrent -and $CloseWaitSeconds -eq 5 }
	}

	It "keeps the current terminal open when KeepTerminalOpen is specified" {
		{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen } | Should -Not -Throw

		Should -Invoke Terminate-WindowsTerminalTabs -Times 0
	}

	Context "-Auto on the empty base configuration" {
		BeforeEach {
			Mock Write-LogWarning { }
		}

		It "leaves the system untouched when Themes is empty" {
			$script:Configuration = [PSCustomObject]@{ Themes = @{} }

			{ Set-SystemTheme -Auto } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Set-Wallpaper -Times 0
			Should -Invoke Set-LockScreenWallpaper -Times 0
			Should -Invoke Restart-Explorer -Times 0
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Themes not configured" }
		}

		It "leaves the system untouched when the machine type has no Themes entry" {
			$script:Configuration = [PSCustomObject]@{ Themes = @{ Laptop = "Dark" } }

			{ Set-SystemTheme -Auto } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 0
			Should -Invoke Set-Wallpaper -Times 0
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "No theme configured" }
		}

		It "still applies the configured theme for the machine type" {
			{ Set-SystemTheme -Auto -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Set-Wallpaper -Times 1
			Should -Invoke Set-LockScreenWallpaper -Times 1
		}
	}

	Context "Built-in step defaults" {
		BeforeEach {
			Mock Write-LogWarning { }
			# Light requested against a Dark machine, so the theme actually changes and
			# the RefreshBrowserTabs step becomes reachable.
			Mock Get-ItemProperty { [PSCustomObject]@{ AppsUseLightTheme = 0 } }
		}

		It "restarts Explorer and applies both wallpapers without reloading browser tabs" {
			{ Set-SystemTheme -Theme "Light" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Set-ItemProperty -Times 3 -Exactly
			Should -Invoke Restart-Explorer -Times 1 -Exactly
			Should -Invoke Set-Wallpaper -Times 1 -Exactly -ParameterFilter { $Auto -and $Theme -eq "Light" }
			Should -Invoke Set-LockScreenWallpaper -Times 1 -Exactly -ParameterFilter { $Theme -eq "Light" }
			Should -Invoke Refresh-BrowserTabs -Times 0
		}

		It "never reloads browser tabs when the theme was already configured" {
			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen -Include RefreshBrowserTabs } | Should -Not -Throw

			Should -Invoke Refresh-BrowserTabs -Times 0
		}
	}

	Context "SystemTheme.Steps config" {
		BeforeEach {
			Mock Write-LogWarning { }
		}

		It "skips the desktop wallpaper when Steps.SetWallpaper is false" {
			$global:Configuration.SystemTheme = @{ Steps = @{ SetWallpaper = $false } }

			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Set-Wallpaper -Times 0
			Should -Invoke Set-LockScreenWallpaper -Times 1 -Exactly
		}

		It "skips the lock screen when Steps.SetLockScreenWallpaper is false" {
			$global:Configuration.SystemTheme = @{ Steps = @{ SetLockScreenWallpaper = $false } }

			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Set-Wallpaper -Times 1 -Exactly
			Should -Invoke Set-LockScreenWallpaper -Times 0
		}

		It "skips the Explorer restart when Steps.RestartExplorer is false" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RestartExplorer = $false } }

			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Restart-Explorer -Times 0
			Should -Invoke Set-Wallpaper -Times 1 -Exactly
		}

		It "reloads browser tabs on a real theme change when Steps.RefreshBrowserTabs is true" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RefreshBrowserTabs = $true } }

			{ Set-SystemTheme -Theme "Light" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Refresh-BrowserTabs -Times 1 -Exactly
		}

		# Resolved against the built-in default (RestartExplorer is on), so this can
		# only pass if the machine-type entry was actually read.
		It "honours a per-machine-type step value" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RestartExplorer = @{ Default = $true; PC = $false } } }

			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen } | Should -Not -Throw

			Should -Invoke Restart-Explorer -Times 0
		}
	}

	Context "Skip and Include overrides" {
		BeforeEach {
			Mock Write-LogWarning { }
		}

		It "forces a config-disabled step on with -Include" {
			$global:Configuration.SystemTheme = @{ Steps = @{ RestartExplorer = $false } }

			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen -Include RestartExplorer } | Should -Not -Throw

			Should -Invoke Restart-Explorer -Times 1 -Exactly
		}

		It "forces config-enabled steps off with -Skip" {
			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen -Skip RestartExplorer, SetWallpaper, SetLockScreenWallpaper } | Should -Not -Throw

			Should -Invoke Restart-Explorer -Times 0
			Should -Invoke Set-Wallpaper -Times 0
			Should -Invoke Set-LockScreenWallpaper -Times 0
		}

		It "lets -Skip win and warns when a step is in both -Skip and -Include" {
			{ Set-SystemTheme -Theme "Dark" -KeepTerminalOpen -Skip SetWallpaper -Include SetWallpaper } | Should -Not -Throw

			Should -Invoke Set-Wallpaper -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "SetWallpaper" }
		}
	}
}

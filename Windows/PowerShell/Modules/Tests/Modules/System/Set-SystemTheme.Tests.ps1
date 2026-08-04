#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Set-SystemTheme.ps1"
}

Describe "Set-SystemTheme" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Themes = @{ PC = "Dark" }
		}
		$script:previousWtSession = $env:WT_SESSION
		$env:WT_SESSION = 'test-session'

		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { "PC" }
		Mock Get-ItemProperty { [PSCustomObject]@{ AppsUseLightTheme = 0 } }
		Mock Set-ItemProperty { }
		Mock Set-Wallpaper { }
		Mock Set-LockScreenWallpaper { }
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
}

#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

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
}

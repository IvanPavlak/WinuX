#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Set-Wallpaper.ps1"
}

Describe "Set-Wallpaper" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			WallpaperStyles        = @{}
			WallpaperDarkSettings  = @{}
			WallpaperLightSettings = @{}
		}

		Mock Test-AdminPrivileges { }
		Mock Get-Module { throw "simulated module query failure" }
		Mock ReRun-LastCommand { }
		Mock Write-Host { }
	}

	It "enters recovery path when wallpaper setup throws" {
		{ Set-Wallpaper } | Should -Not -Throw

		Should -Invoke ReRun-LastCommand -Times 1
	}

	It "-Auto leaves the wallpaper as-is when the settings are empty (empty base)" {
		Mock Get-Module { $null }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }

		{ Set-Wallpaper -Auto -Theme "Dark" } | Should -Not -Throw

		Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Wallpaper settings not configured" }
		Should -Invoke ReRun-LastCommand -Times 0
	}
}

#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

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
}

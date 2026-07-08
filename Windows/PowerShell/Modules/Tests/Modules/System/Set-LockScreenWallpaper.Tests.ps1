#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-LockScreenWallpaper.ps1"
}

Describe "Set-LockScreenWallpaper" {
	BeforeEach {
		$global:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{
					Wallpapers = "C:\\Wallpapers"
				}
			}
		}

		$script:Configuration = [PSCustomObject]@{
			WallpaperDarkSettings  = @{ PC = @{ File = "dark.jpg" } }
			WallpaperLightSettings = @{ PC = @{ File = "light.jpg" } }
		}

		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { "PC" }
		Mock Test-Path { $false }
		Mock Set-ItemProperty { }
		Mock ReRun-LastCommand { }
		Mock Write-Host { }
	}

	It "returns when the selected lock screen wallpaper file is missing" {
		{ Set-LockScreenWallpaper -Theme "Dark" } | Should -Not -Throw

		Should -Invoke DetermineMachineType -Times 1
		Should -Invoke Set-ItemProperty -Times 0
	}
}

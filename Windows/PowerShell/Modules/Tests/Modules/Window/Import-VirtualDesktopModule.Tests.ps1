#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Import-VirtualDesktopModule" {
	BeforeEach {
		Mock Write-Warning { } -ModuleName Window
		# Reset the module-scoped state before each test
		& (Get-Module Window) {
			$script:VirtualDesktopState = @{
				Checked   = $false
				Available = $false
				Loaded    = $false
			}
		}
	}

	Context "When module is not installed" {
		It "Should return false" {
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { -not $ListAvailable }

			$result = Import-VirtualDesktopModule

			$result | Should -Be $false
		}

		It "Should warn when not silent" {
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { -not $ListAvailable }

			Import-VirtualDesktopModule

			Should -Invoke Write-Warning -ModuleName Window -Times 1
		}

		It "Should not warn when silent" {
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { -not $ListAvailable }

			Import-VirtualDesktopModule -Silent

			Should -Invoke Write-Warning -ModuleName Window -Times 0
		}
	}

	Context "When module is installed but not loaded" {
		It "Should import and return true" {
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { $Name -eq "VirtualDesktop" -and -not $ListAvailable }
			Mock Import-Module { } -ModuleName Window

			$result = Import-VirtualDesktopModule

			$result | Should -Be $true
		}
	}

	Context "When module is already loaded" {
		It "Should return true without re-importing" {
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window -ParameterFilter { $Name -eq "VirtualDesktop" -and -not $ListAvailable }
			Mock Import-Module { } -ModuleName Window

			$result = Import-VirtualDesktopModule

			$result | Should -Be $true
			Should -Invoke Import-Module -ModuleName Window -Times 0
		}
	}

	Context "When import fails" {
		It "Should return false" {
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window -ParameterFilter { $ListAvailable }
			Mock Get-Module { $null } -ModuleName Window -ParameterFilter { $Name -eq "VirtualDesktop" -and -not $ListAvailable }
			Mock Import-Module { throw "Load failed" } -ModuleName Window

			$result = Import-VirtualDesktopModule

			$result | Should -Be $false
		}
	}

	Context "Caching behavior" {
		It "Should return true immediately when state is already loaded" {
			& (Get-Module Window) {
				$script:VirtualDesktopState = @{
					Checked   = $true
					Available = $true
					Loaded    = $true
				}
			}

			$result = Import-VirtualDesktopModule

			$result | Should -Be $true
		}
	}
}

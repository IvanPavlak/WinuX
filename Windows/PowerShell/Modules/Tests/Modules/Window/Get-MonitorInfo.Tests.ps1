#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-MonitorInfo.ps1"
}

Describe "Get-MonitorInfo" {
	BeforeEach {
		Mock Ensure-WindowsFormsLoaded { }
		Mock Write-Host { }
		Mock Write-Error { }
	}

	It "maps cached screen info to monitor objects" {
		$screen = [PSCustomObject]@{
			DeviceName  = "\\.\\DISPLAY1"
			Primary     = $true
			Bounds      = [PSCustomObject]@{ Left = 0; Top = 0; Right = 1920; Bottom = 1080; Width = 1920; Height = 1080 }
			WorkingArea = [PSCustomObject]@{ Left = 0; Top = 0; Right = 1920; Bottom = 1040; Width = 1920; Height = 1040 }
		}
		Mock Get-CachedMonitors { @($screen) }

		$result = Get-MonitorInfo -Quiet

		$result.Count | Should -Be 1
		$result[0].DeviceName | Should -Be "\\.\\DISPLAY1"
		$result[0].WorkAreaHeight | Should -Be 1040
	}

	It "returns empty array when monitor retrieval throws" {
		Mock Get-CachedMonitors { throw "boom" }

		$result = Get-MonitorInfo -Quiet

		$result.Count | Should -Be 0
		Should -Invoke Write-Error -Times 1
	}
}

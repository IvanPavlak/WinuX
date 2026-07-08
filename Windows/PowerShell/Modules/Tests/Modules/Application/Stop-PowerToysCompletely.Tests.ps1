#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Stop-PowerToysCompletely.ps1"
}

Describe "Stop-PowerToysCompletely" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Start-Sleep { }
		Mock Stop-Process { }
		Mock taskkill { }
	}

	It "returns true when no PowerToys processes are running" {
		Mock Get-Process { @() }

		$result = Stop-PowerToysCompletely

		$result | Should -BeTrue
		Should -Invoke Stop-Process -Times 0
	}

	It "attempts force-stop escalation when processes persist" {
		Mock Get-Process {
			param($Name)
			if ($Name -ne 'PowerToys*') {
				return @()
			}

			return @(
				[PSCustomObject]@{ ProcessName = 'PowerToys'; Id = 1001; HasExited = $false; MainWindowHandle = 55 }
			)
		}

		Mock Stop-Process { }

		$result = Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 100

		$result | Should -BeFalse
		Should -Invoke Stop-Process -Times 1
		Should -Invoke taskkill -Times 1
	}
}

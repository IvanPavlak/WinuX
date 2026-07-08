#Requires -Modules Pester

BeforeAll {
	$script:OriginalLocalAppData = $env:LOCALAPPDATA
	$script:OriginalProgramFiles = $env:ProgramFiles
	$script:OriginalProgramFilesX86 = ${env:ProgramFiles(x86)}

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Stop-PowerToysCompletely.ps1"
	. "$AppFunctionsPath\Start-FancyZones.ps1"
}

AfterAll {
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
	$env:ProgramFiles = $script:OriginalProgramFiles
	${env:ProgramFiles(x86)} = $script:OriginalProgramFilesX86
}

Describe "Start-FancyZones" {
	BeforeEach {
		$env:LOCALAPPDATA = 'C:\Users\You\AppData\Local'
		$env:ProgramFiles = 'C:\Program Files'
		${env:ProgramFiles(x86)} = 'C:\Program Files (x86)'

		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Write-Error { }
		Mock Start-Sleep { }
		Mock Stop-Process { }
		Mock taskkill { }
		Mock Start-Process { }
		Mock Loading-Spinner { @{ Label = $Label; Timer = $null; EventSubscription = $null } }
		Mock Get-Content { '{"ok":true}' }
		Mock ConvertFrom-Json { @{ ok = $true } }
		Mock Test-RpcServerHealth { $true }
		Mock Test-Path { $false }
	}

	It "returns true without restart when FancyZones process is running and readiness checks pass" {
		Mock Get-Process {
			param($Name)
			if ($Name -eq 'PowerToys.FancyZones') {
				return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false }
			}
			return $null
		}
		Mock Test-Path {
			param($Path)
			if ($Path -like '*Microsoft\PowerToys\FancyZones') { return $true }
			return $false
		}

		$result = Start-FancyZones

		$result | Should -BeTrue
		Should -Invoke Start-Process -Times 0
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}

	It "returns false when FancyZones is not running and PowerToys executable is not found" {
		Mock Get-Process { $null }
		Mock Test-Path { $false }

		$result = Start-FancyZones

		$result | Should -BeFalse
		Should -Invoke Start-Process -Times 0
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}
}

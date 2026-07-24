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

		# The readiness cache is module-scoped in production (test-script-scoped here
		# because the function is dot-sourced) - reset so each test starts uncached.
		$script:FancyZonesReadyCache = $null
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

	Context "Readiness caching and PID sampling" {
		BeforeEach {
			Mock Test-Path {
				param($Path)
				if ($Path -like '*Microsoft\PowerToys\FancyZones') { return $true }
				return $false
			}
		}

		It "takes a single process sample when FancyZones has been alive for a while" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones') {
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$result = Start-FancyZones

			$result | Should -BeTrue
			# A long-lived process cannot be mid-crash-loop: no PID-stability sampling
			# (which cost a fixed 3x250ms). Two lookups total: the outer process check
			# plus the single readiness sample.
			Should -Invoke Get-Process -Times 2 -Exactly -ParameterFilter { $Name -eq 'PowerToys.FancyZones' }
			Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Milliseconds -eq 250 }
		}

		It "keeps the full PID-stability sampling for a freshly started process" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones') {
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date) }
				}
				return $null
			}

			$result = Start-FancyZones

			$result | Should -BeTrue
			Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Milliseconds -eq 250 }
		}

		It "serves repeat calls from the ready-cache without re-probing" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones') {
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$null = Start-FancyZones
			$result = Start-FancyZones

			$result | Should -BeTrue
			# One workspace open calls Start-FancyZones several times seconds apart - only
			# the first call pays the readiness probe (service checks + JSON parses).
			Should -Invoke Test-RpcServerHealth -Times 1 -Exactly
		}
	}
}

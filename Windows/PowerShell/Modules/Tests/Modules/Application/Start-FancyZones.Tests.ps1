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

		$result = Start-FancyZones -PassThru

		$result | Should -BeTrue
		Should -Invoke Start-Process -Times 0
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}

	It "returns false when FancyZones is not running and PowerToys executable is not found" {
		Mock Get-Process { $null }
		Mock Test-Path { $false }

		$result = Start-FancyZones -PassThru

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

			$result = Start-FancyZones -PassThru

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

			$result = Start-FancyZones -PassThru

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
			$result = Start-FancyZones -PassThru

			$result | Should -BeTrue
			# One workspace open calls Start-FancyZones several times seconds apart - only
			# the first call pays the readiness probe (service checks + JSON parses).
			Should -Invoke Test-RpcServerHealth -Times 1 -Exactly
		}

		It "shows no spinner for a call served from the ready-cache" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones') {
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$null = Start-FancyZones
			$null = Start-FancyZones
			$null = Start-FancyZones

			# A cached call does no work, so it must not announce any. The spinner used to be
			# started before the cache was consulted, so three back-to-back calls (which one
			# retry reset produces) printed three "Starting FancyZones" lines for one restart.
			Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Start }
			Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Stop }
		}

		It "emits nothing without -PassThru so an interactive call prints no True" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones') {
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$output = Start-FancyZones

			$output | Should -BeNullOrEmpty
		}
	}

	Context "Startup polling after launching PowerToys" {
		BeforeEach {
			# FancyZones is not running; PowerToys.exe is installed under Program Files.
			Mock Test-Path {
				param($Path)
				if ($Path -like '*Microsoft\PowerToys\FancyZones') { return $true }
				if ($Path -eq 'C:\Program Files\PowerToys\PowerToys.exe') { return $true }
				return $false
			}

			$script:powerToysLaunched = $false
			$script:fancyZonesLookupsAfterLaunch = 0
			Mock Start-Process { $script:powerToysLaunched = $true }
		}

		It "checks readiness immediately after launching PowerToys instead of sleeping first" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones' -and $script:powerToysLaunched) {
					# Old enough to skip the PID-stability sampling, so the only sleeps left would
					# be the poll's own.
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$result = Start-FancyZones -PassThru

			$result | Should -BeTrue
			Should -Invoke Start-Process -Times 1 -Exactly
			# The first readiness check runs before any poll sleep - the old loop slept 500 ms
			# first. The only sleep left is the 50 ms post-readiness settle.
			Should -Invoke Start-Sleep -Times 0 -Exactly -ParameterFilter { $Milliseconds -ge 100 }
		}

		It "polls every 100 ms until the FancyZones process is enumerable" {
			Mock Get-Process {
				param($Name)
				if ($Name -eq 'PowerToys.FancyZones' -and $script:powerToysLaunched) {
					$script:fancyZonesLookupsAfterLaunch++
					if ($script:fancyZonesLookupsAfterLaunch -le 3) { return $null }
					return [PSCustomObject]@{ Id = 4321; ProcessName = 'PowerToys.FancyZones'; HasExited = $false; StartTime = (Get-Date).AddMinutes(-30) }
				}
				return $null
			}

			$result = Start-FancyZones -PassThru

			$result | Should -BeTrue
			# Three empty lookups, three 100 ms polls, then the process is picked up.
			Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Milliseconds -eq 100 }
			Should -Invoke Start-Sleep -Times 0 -Exactly -ParameterFilter { $Milliseconds -eq 500 }
		}

		It "gives up at the -MaxWaitSeconds deadline when FancyZones never appears" {
			Mock Get-Process { $null }

			$result = Start-FancyZones -MaxWaitSeconds 0 -PassThru

			$result | Should -BeFalse
			Should -Invoke Start-Process -Times 1 -Exactly
			Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Stop -and $Discard }
		}
	}
}

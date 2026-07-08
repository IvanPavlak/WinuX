#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\DockerWizard.ps1"

	function Loading-Spinner {
		param(
			[switch]$Start,
			[switch]$Stop,
			[string]$Label,
			$Spinner
		)
		if ($Start) {
			return [PSCustomObject]@{ Id = 'spinner' }
		}
	}

	function Open-Docker { }
}

Describe "DockerWizard" {
	BeforeEach {
		$script:dockerDesktopVersionCall = 0
		$script:dockerDesktopStopCall = 0
		$script:dockerDesktopStartCall = 0
		$script:dockerInfoCall = 0
		$script:dockerComposePsCall = 0
		$script:dockerComposeUpCall = 0
		$script:wslListQCall = 0
		$script:wslListVCall = 0
		$script:wslTerminateCalls = @()

		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Get-Command { [PSCustomObject]@{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
		Mock Loading-Spinner {
			param([switch]$Start, [switch]$Stop, [string]$Label, $Spinner)
			if ($Start) { [PSCustomObject]@{ Id = 'spinner' } }
		}
		Mock Open-Docker { }
		Mock Get-Process { @() }
		Mock Get-CimInstance { @() }
		Mock Stop-Process { }
		Mock Test-Path { $false }

		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'version') {
				$script:dockerDesktopVersionCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'stop') {
				$script:dockerDesktopStopCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'start') {
				$script:dockerDesktopStartCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 1 -and $cmd[0] -eq 'info') {
				$script:dockerInfoCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 4 -and $cmd[0] -eq 'compose' -and $cmd[1] -eq '-f' -and $cmd[3] -eq 'ps') {
				$script:dockerComposePsCall++
				$global:LASTEXITCODE = 0
				return @()
			}
			if ($cmd.Count -ge 4 -and $cmd[0] -eq 'compose' -and $cmd[1] -eq '-f' -and $cmd[3] -eq 'up') {
				$script:dockerComposeUpCall++
				$global:LASTEXITCODE = 0
				return
			}
			$global:LASTEXITCODE = 0
		}

		Mock wsl.exe {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-q') {
				$script:wslListQCall++
				return @()
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-v') {
				$script:wslListVCall++
				return ''
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '--terminate') {
				$script:wslTerminateCalls += $cmd[1]
				return
			}
		}
	}

	It "Stop exits early when Docker is already fully stopped" {
		DockerWizard -Stop

		$script:dockerDesktopStopCall | Should -Be 0
		Should -Invoke Loading-Spinner -Times 0
	}

	It "Stop requests graceful docker desktop stop when not fully stopped" {
		Mock Get-Process {
			@([PSCustomObject]@{ Name = 'Docker Desktop'; Id = 123 })
		}

		DockerWizard -Stop

		$script:dockerDesktopStopCall | Should -Be 1
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}

	It "Start exits early when daemon is already running and no compose path is requested" {
		DockerWizard

		$script:dockerDesktopStartCall | Should -Be 0
		Should -Invoke Open-Docker -Times 0
	}

	It "starts compose services when daemon is running and compose file is provided" {
		Mock Test-Path {
			$Path -eq 'C:\repo\docker-compose.yml'
		}

		DockerWizard -ComposeFilePath 'C:\repo\docker-compose.yml'

		$script:dockerComposePsCall | Should -Be 1
		$script:dockerComposeUpCall | Should -Be 1
	}

	It "starts Docker via Open-Docker when docker desktop CLI is unavailable" {
		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'version') {
				$global:LASTEXITCODE = 1
				return
			}
			if ($cmd.Count -ge 1 -and $cmd[0] -eq 'info') {
				$script:dockerInfoCall++
				if ($script:dockerInfoCall -le 1) {
					$global:LASTEXITCODE = 1
				}
				else {
					$global:LASTEXITCODE = 0
				}
				return
			}
			$global:LASTEXITCODE = 0
		}

		DockerWizard

		Should -Invoke Open-Docker -Times 1
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}

	It "Stop fallback terminates docker WSL distros and docker-owned wsl processes" {
		$script:cleanupCompleted = $false

		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'version') {
				$global:LASTEXITCODE = 1
				return
			}
			$global:LASTEXITCODE = 0
		}

		Mock Get-Process {
			param($Name)
			if ($script:cleanupCompleted) { return @() }
			@([PSCustomObject]@{ Name = 'Docker Desktop'; Id = 1234 })
		}

		Mock Get-CimInstance {
			param($ClassName, $Filter)
			if ($script:cleanupCompleted) { return @() }
			@(
				[PSCustomObject]@{ ProcessId = 9001; CommandLine = 'wsl.exe -d docker-desktop sh' },
				[PSCustomObject]@{ ProcessId = 9002; CommandLine = 'wsl.exe -d Ubuntu sh' }
			)
		}

		Mock wsl.exe {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-q') {
				return @('docker-desktop', 'docker-desktop-data', 'Ubuntu')
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-v') {
				if ($script:cleanupCompleted) {
					return '  Ubuntu    Stopped 2'
				}
				return @(
					'  docker-desktop       Running 2',
					'  docker-desktop-data  Running 2',
					'  Ubuntu               Running 2'
				)
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '--terminate') {
				$script:wslTerminateCalls += $cmd[1]
				if ($script:wslTerminateCalls.Count -ge 2) { $script:cleanupCompleted = $true }
				return
			}
		}

		DockerWizard -Stop

		$script:wslTerminateCalls | Should -Contain 'docker-desktop'
		$script:wslTerminateCalls | Should -Contain 'docker-desktop-data'
		Should -Invoke Stop-Process -Times 1
	}

	It "sets DockerStartFailed when daemon does not become ready within timeout" {
		$script:DockerStartFailed = $false

		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'version') {
				$script:dockerDesktopVersionCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 2 -and $cmd[0] -eq 'desktop' -and $cmd[1] -eq 'start') {
				$script:dockerDesktopStartCall++
				$global:LASTEXITCODE = 0
				return
			}
			if ($cmd.Count -ge 1 -and $cmd[0] -eq 'info') {
				$script:dockerInfoCall++
				$global:LASTEXITCODE = 1
				return
			}
			$global:LASTEXITCODE = 0
		}

		Mock Get-Process { @() }
		Mock Get-CimInstance { @() }
		Mock wsl.exe {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-q') { return @() }
			if ($cmd.Count -ge 2 -and $cmd[0] -eq '-l' -and $cmd[1] -eq '-v') { return '' }
		}

		DockerWizard

		$script:DockerStartFailed | Should -BeTrue
		$script:dockerDesktopStartCall | Should -Be 1
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Start }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Stop }
	}
}

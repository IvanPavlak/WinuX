#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Stop-PowerToysCompletely.ps1"

	# Process double. Get-Process hands the function System.Diagnostics.Process objects in
	# production; these carry only the members the function touches. CloseMainWindow() reports
	# -CloseDelivered (what the real call returns when a WM_CLOSE was posted) and, with
	# -ExitsOnClose, empties the fake process table two Get-Process polls later, like a real
	# graceful shutdown. -WithWaitForExit adds the handle wait the real object has.
	function New-FakePowerToysProcess {
		param(
			[string]$Name = 'PowerToys',
			[int]$Id = 1001,
			[int]$MainWindowHandle = 0,
			[bool]$CloseDelivered = $true,
			[switch]$ExitsOnClose,
			[switch]$WithWaitForExit
		)

		$process = [PSCustomObject]@{
			ProcessName      = $Name
			Id               = $Id
			HasExited        = $false
			MainWindowHandle = $MainWindowHandle
			CloseDelivered   = $CloseDelivered
			ExitsOnClose     = [bool]$ExitsOnClose
		}

		$process | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value {
			$script:closeMainWindowCalls++
			if ($this.ExitsOnClose) {
				$script:pollsUntilGracefulExit = 2
			}
			return $this.CloseDelivered
		}

		if ($WithWaitForExit) {
			$process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
				param([int]$TimeoutMs)
				$script:waitForExitCalls++
				return $true
			}
		}

		return $process
	}
}

Describe "Stop-PowerToysCompletely" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Warning { }
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		Mock taskkill { }

		# Fake process table: Get-Process reads it, Stop-Process removes from it, and a graceful
		# exit empties it after the polls CloseMainWindow() scheduled.
		$script:fakeProcesses = @()
		$script:closeMainWindowCalls = 0
		$script:waitForExitCalls = 0
		$script:pollsUntilGracefulExit = $null

		Mock Get-Process {
			param($Name)
			if ($Name -ne 'PowerToys*') {
				return @()
			}

			if ($null -ne $script:pollsUntilGracefulExit) {
				if ($script:pollsUntilGracefulExit -le 0) {
					$script:fakeProcesses = @()
				}
				$script:pollsUntilGracefulExit--
			}

			return @($script:fakeProcesses)
		}

		Mock Stop-Process {
			param($Id)
			# The mock carries Stop-Process's real signature, so -Id arrives as [int[]] even for a
			# single PID, and a scalar -ne against that array never matches - hence -notcontains.
			$stoppedIds = @($Id)
			$script:fakeProcesses = @($script:fakeProcesses | Where-Object { $stoppedIds -notcontains $_.Id })
		}
	}

	It "returns true when no PowerToys processes are running" {
		$result = Stop-PowerToysCompletely

		$result | Should -BeTrue
		Should -Invoke Stop-Process -Times 0 -Exactly
	}

	It "skips the graceful wait when PowerToys has no main window to close" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -MainWindowHandle 0),
			(New-FakePowerToysProcess -Name 'PowerToys.FancyZones' -Id 1002)
		)

		$result = Stop-PowerToysCompletely -PreferGracefulExit

		$result | Should -BeTrue
		# PowerToys.exe is a tray application: MainWindowHandle 0 means there is nothing to post
		# WM_CLOSE to, so no request goes out and none of the 30 graceful polls (3 s at the default
		# -MaxGracefulWaitMs) may run - the restart goes straight to the kills.
		$script:closeMainWindowCalls | Should -Be 0
		Should -Invoke Stop-Process -Times 2 -Exactly
		# The one sleep is the 100 ms settle after kills whose exit could not be observed.
		Should -Invoke Start-Sleep -Times 1 -Exactly
	}

	It "waits for the graceful exit only after CloseMainWindow delivered the request" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -MainWindowHandle 55 -CloseDelivered $true -ExitsOnClose)
		)

		$result = Stop-PowerToysCompletely -PreferGracefulExit

		$result | Should -BeTrue
		$script:closeMainWindowCalls | Should -Be 1
		# Two polls until the fake exited gracefully, then nothing left to force-stop.
		Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Milliseconds -eq 100 }
		Should -Invoke Stop-Process -Times 0 -Exactly
	}

	It "does not wait when CloseMainWindow reports the close message was not posted" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -MainWindowHandle 55 -CloseDelivered $false)
		)

		$result = Stop-PowerToysCompletely -PreferGracefulExit

		$result | Should -BeTrue
		$script:closeMainWindowCalls | Should -Be 1
		Should -Invoke Stop-Process -Times 1 -Exactly
		Should -Invoke Start-Sleep -Times 1 -Exactly
	}

	It "stops polling at -MaxGracefulWaitMs when the graceful exit never completes" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -MainWindowHandle 55 -CloseDelivered $true)
		)

		$result = Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 300

		$result | Should -BeTrue
		# Three 100 ms polls, then the force path with its one settle sleep.
		Should -Invoke Start-Sleep -Times 4 -Exactly -ParameterFilter { $Milliseconds -eq 100 }
		Should -Invoke Stop-Process -Times 1 -Exactly
	}

	It "waits on each killed process handle instead of escalating against a process that is still exiting" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -WithWaitForExit),
			(New-FakePowerToysProcess -Name 'PowerToys.FancyZones' -Id 1002 -WithWaitForExit)
		)

		$result = Stop-PowerToysCompletely -PreferGracefulExit

		$result | Should -BeTrue
		# Process.Kill() is asynchronous; the handle wait is the exact "it is gone" signal. With
		# it observed for every kill there is no settle sleep and no tree kill.
		$script:waitForExitCalls | Should -Be 2
		Should -Invoke Stop-Process -Times 2 -Exactly
		Should -Invoke taskkill -Times 0 -Exactly
		Should -Invoke Start-Sleep -Times 0 -Exactly
	}

	It "attempts force-stop escalation when processes persist" {
		$script:fakeProcesses = @(
			(New-FakePowerToysProcess -Name 'PowerToys' -Id 1001 -MainWindowHandle 55 -CloseDelivered $false)
		)
		# A kill that does not land: the process stays in the table.
		Mock Stop-Process { }

		$result = Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 100

		$result | Should -BeFalse
		Should -Invoke Stop-Process -Times 1
		Should -Invoke taskkill -Times 1
	}
}

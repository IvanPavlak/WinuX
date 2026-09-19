#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-WSLTab.ps1"

	function Get-NewTabArguments {
		param([hashtable]$Parameters = @{})

		$script:capturedArguments = $null
		Mock Start-Process { $script:capturedArguments = @($ArgumentList) }

		Open-WSLTab @Parameters

		, @($script:capturedArguments)
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-WSLTab" {
	BeforeEach {
		$global:Configuration = @{ DefaultWSLDistribution = 'Ubuntu-22.04' }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Start-Sleep { }
		Mock Start-Process { }

		# A shell descended from an Open-Workspace -Alongside bootstrap carries a real
		# WT_WINDOW_ID, which the caller-window resolution prefers over "0" - clear it so the
		# window-id assertions are deterministic regardless of where the run was started from.
		$script:previousWtWindowId = $env:WT_WINDOW_ID
		Remove-Item Env:WT_WINDOW_ID -ErrorAction SilentlyContinue
	}

	AfterEach {
		if ($null -ne $script:previousWtWindowId) {
			$env:WT_WINDOW_ID = $script:previousWtWindowId
		}
		else {
			Remove-Item Env:WT_WINDOW_ID -ErrorAction SilentlyContinue
		}
	}

	It "opens a bare tab in the caller's window on the configured distribution" {
		$arguments = Get-NewTabArguments

		$arguments | Should -Be @("-w", "0", "new-tab", "-p", "Ubuntu-22.04")
	}

	It "logs the title and the success line when it is not quiet" {
		Open-WSLTab

		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogSuccess -Times 1
	}

	It "says nothing when it is quiet" {
		Open-WSLTab -Quiet

		Should -Invoke Start-Process -Times 1
		Should -Invoke Write-LogTitle -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "opens no tab when no distribution is configured" {
		$global:Configuration = @{ DefaultWSLDistribution = "" }

		Open-WSLTab -Quiet

		Should -Invoke Start-Process -Times 0
	}

	It "prefers an explicitly named distribution over the configured one" {
		$arguments = Get-NewTabArguments -Parameters @{ Distribution = "Debian" }

		$arguments | Should -Be @("-w", "0", "new-tab", "-p", "Debian")
	}

	It "titles the tab when a title is given" {
		$arguments = Get-NewTabArguments -Parameters @{ TabTitle = "Demo.WSL" }

		$titleIndex = [Array]::IndexOf($arguments, "--title")
		$titleIndex | Should -BeGreaterThan -1
		$arguments[$titleIndex + 1] | Should -Be "Demo.WSL"
	}

	It "starts the tab in a path by overriding the tab's commandline" {
		# `wt -d` cannot do it: it sets the Win32 working directory of the profile process, so a
		# WSL path is refused outright and a Windows one still loses to the profile's `--cd ~`.
		# Only a commandline handed to new-tab lands the tab inside the directory.
		$arguments = Get-NewTabArguments -Parameters @{ Path = "/mnt/c/Dev/Demo"; TabTitle = "Demo.WSL" }

		$cdIndex = [Array]::IndexOf($arguments, "--cd")
		$cdIndex | Should -BeGreaterThan -1
		$arguments[$cdIndex + 1] | Should -Be "/mnt/c/Dev/Demo"
		$arguments | Should -Contain "wsl.exe"
	}

	It "passes the path through untranslated" {
		# The path is a path in the distribution's own file system - translating /mnt/c/... to a
		# Windows path would break the one case the parameter exists for.
		$arguments = Get-NewTabArguments -Parameters @{ Path = "/mnt/c/Dev/Demo" }

		$arguments | Should -Not -Contain "C:\Dev\Demo"
		$arguments | Should -Contain "/mnt/c/Dev/Demo"
	}

	It "opens the tab in the window it is given" {
		$arguments = Get-NewTabArguments -Parameters @{ WindowId = "project-window" }

		$arguments[0] | Should -Be "-w"
		$arguments[1] | Should -Be "project-window"
	}
}

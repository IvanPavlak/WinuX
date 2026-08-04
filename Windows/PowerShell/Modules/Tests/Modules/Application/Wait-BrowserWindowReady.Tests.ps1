#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$AppFunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	. "$AppFunctionsPath\Wait-BrowserWindowReady.ps1"
}

Describe "Wait-BrowserWindowReady" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
	}

	It "returns true immediately when a window already exists" {
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Brave' })
		}

		Wait-BrowserWindowReady -ProcessName "brave" | Should -BeTrue

		Should -Invoke Start-Sleep -Times 0
	}

	It "filters candidate windows by title pattern" {
		# A regular Firefox window must not satisfy a wait for Tor Browser.
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'WinuX - Mozilla Firefox' })
		}

		Wait-BrowserWindowReady -ProcessName "firefox" -TitlePattern "Tor Browser" -TimeoutSeconds 1 | Should -BeFalse
	}

	It "returns false and logs when no window appears before the timeout" {
		Mock Get-WindowHandle { @() }

		Wait-BrowserWindowReady -ProcessName "brave" -TimeoutSeconds 1 | Should -BeFalse

		Should -Invoke Write-LogDebug -Times 1
	}

	It "keeps polling until a window appears" {
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -ge 3) {
				@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Brave' })
			}
			else {
				@()
			}
		}

		Wait-BrowserWindowReady -ProcessName "brave" -TimeoutSeconds 5 | Should -BeTrue

		$script:pollCount | Should -Be 3
	}
}

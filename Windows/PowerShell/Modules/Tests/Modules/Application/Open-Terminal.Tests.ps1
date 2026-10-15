#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	. "$FunctionsPath\Open-Terminal.ps1"

	# Window ID 0 activates the caller's own window first. Stand-ins so the mocks below exist even
	# when the Helper and Window modules are not loaded, and no test touches a real window.
	function Resolve-HostingTerminalTab { }
	function Set-WindowForeground { param([IntPtr]$Handle) }
	function Write-LogDebug { param($Message, $Style) }
}

Describe "Open-Terminal" {
	BeforeEach {
		Mock Start-Process { }
		Mock Start-Sleep { }
		Mock Resolve-HostingTerminalTab { $null }
		Mock Set-WindowForeground { $true }
		Mock Write-LogDebug { }

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

	Context "Parameter validation" {
		It "Should have Command parameter" {
			$cmd = Get-Command Open-Terminal
			$cmd.Parameters.ContainsKey('Command') | Should -BeTrue
		}

		It "Should have Administrator parameter" {
			$cmd = Get-Command Open-Terminal
			$cmd.Parameters.ContainsKey('Administrator') | Should -BeTrue
		}

		It "Should have InSameShell parameter" {
			$cmd = Get-Command Open-Terminal
			$cmd.Parameters.ContainsKey('InSameShell') | Should -BeTrue
		}

		It "Should have WindowId parameter" {
			$cmd = Get-Command Open-Terminal
			$cmd.Parameters.ContainsKey('WindowId') | Should -BeTrue
		}

		It "Should have TabTitles parameter" {
			$cmd = Get-Command Open-Terminal
			$cmd.Parameters.ContainsKey('TabTitles') | Should -BeTrue
		}

		It "Should have WindowId as string type" {
			$cmd = Get-Command Open-Terminal
			$param = $cmd.Parameters['WindowId']
			$param.ParameterType.Name | Should -Be 'String'
		}
	}

	Context "When WindowId is explicitly provided" {
		It "Should use the provided WindowId" {
			$testId = "test-window-id-123"

			Open-Terminal -Command "echo test" -WindowId $testId

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains $testId
			}
		}

		It "Should use WindowId over InSameShell" {
			$testId = "explicit-id"

			Open-Terminal -Command "echo test" -WindowId $testId -InSameShell

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains $testId
			}
		}
	}

	Context "When no command is provided" {
		It "Should open terminal without errors" {
			{ Open-Terminal } | Should -Not -Throw
		}

		It "Should call Start-Process for wt" {
			Open-Terminal

			Should -Invoke Start-Process -Times 1
		}
	}

	Context "When opening with Administrator" {
		It "Should use RunAs verb" {
			Open-Terminal -Administrator

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$Verb -eq 'RunAs'
			}
		}
	}

	Context "Batched tab creation" {
		It "Should chain multiple tabs into ONE wt invocation with ';' separators" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo one", "echo two", "echo three" -TabTitles "A", "B", "C" -WindowId "batch-window"

			# One spawn total - not one per tab with settle sleeps between.
			Should -Invoke Start-Process -Times 1 -Exactly
			# Standalone ";" arguments separate the new-tab subcommands (WT processes the
			# subcommands of one command line strictly in order).
			@($script:capturedArgs | Where-Object { $_ -eq ';' }).Count | Should -Be 2
			@($script:capturedArgs | Where-Object { $_ -eq 'new-tab' }).Count | Should -Be 3
			# The window id is passed once, up front.
			$script:capturedArgs[0] | Should -Be '-w'
			$script:capturedArgs[1] | Should -Be 'batch-window'
		}

		It "Should preserve tab order within the chained invocation" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo one", "echo two" -TabTitles "First", "Second" -WindowId "batch-window"

			$firstIndex = [Array]::IndexOf($script:capturedArgs, 'First')
			$secondIndex = [Array]::IndexOf($script:capturedArgs, 'Second')
			$firstIndex | Should -BeGreaterThan -1
			$secondIndex | Should -BeGreaterThan $firstIndex
		}

		It "Should not sleep between tabs of one batch" {
			Open-Terminal -Command "echo one", "echo two", "echo three" -WindowId "batch-window"

			Should -Invoke Start-Sleep -Times 0
		}
	}

	Context "Tab titles" {
		It "Should title a tab left without a TabTitles entry after the shell" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo test" -WindowId "untitled-window"

			# Without --title Windows Terminal names the tab after the pwsh.exe command line
			# it was handed - and passes that same string to the shell as its console title.
			$titleIndex = [Array]::IndexOf($script:capturedArgs, '--title')
			$titleIndex | Should -BeGreaterThan -1
			$script:capturedArgs[$titleIndex + 1] | Should -Be 'PowerShell'
		}

		It "Should not suppress the application title for an untitled tab" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo test" -WindowId "untitled-window"

			# The shell must stay free to retitle its own tab: Open-Workspace's -Alongside window
			# probe and Terminate-WindowsTerminalTabs' marker both depend on that.
			$script:capturedArgs | Should -Not -Contain '--suppressApplicationTitle'
		}

		It "Should title only the untitled tabs of a mixed batch after the shell" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo one", "echo two" -TabTitles "First" -WindowId "batch-window"

			$titles = @()
			for ($i = 0; $i -lt $script:capturedArgs.Count; $i++) {
				if ($script:capturedArgs[$i] -eq '--title') { $titles += $script:capturedArgs[$i + 1] }
			}
			$titles | Should -Be @('First', 'PowerShell')
		}

		It "Should keep suppressing the application title for explicitly titled tabs" {
			$script:capturedArgs = $null
			Mock Start-Process { $script:capturedArgs = @($ArgumentList) }

			Open-Terminal -Command "echo one" -TabTitles "First" -WindowId "batch-window"

			@($script:capturedArgs | Where-Object { $_ -eq '--suppressApplicationTitle' }).Count | Should -Be 1
		}
	}

	Context "When InSameShell is specified without WindowId" {
		It "Should use window ID 0 when WT_WINDOW_ID is not set" {
			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains "0"
			}
		}

		It "Should prefer WT_WINDOW_ID over window ID 0 when the calling shell knows its window" {
			$env:WT_WINDOW_ID = "caller-window-guid"

			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains "caller-window-guid"
			}
		}

		It "Should use an explicit WindowId over WT_WINDOW_ID" {
			$env:WT_WINDOW_ID = "caller-window-guid"

			Open-Terminal -Command "echo test" -WindowId "explicit-id" -InSameShell

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains "explicit-id"
			}
		}
	}

	Context "Activating the caller's window for window ID 0" {
		# "wt -w 0" lands in the most recently activated terminal window, so the caller's own
		# window is activated first - otherwise a second window that came forward during the
		# command receives the tabs.
		BeforeEach {
			$script:calls = [System.Collections.Generic.List[string]]::new()
			Mock Resolve-HostingTerminalTab { [PSCustomObject]@{ Handle = [IntPtr]4242; ProcessId = 1; TabTitle = 'PowerShell'; Exact = $true } }
			Mock Set-WindowForeground { $script:calls.Add("activate $Handle"); $true }
			Mock Start-Process { $script:calls.Add('spawn') }
		}

		It "activates the identified window before spawning the tabs" {
			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Set-WindowForeground -Times 1 -Exactly -ParameterFilter { $Handle -eq [IntPtr]4242 }
			$script:calls | Should -Be @('activate 4242', 'spawn')
		}

		It "activates it for an explicit window ID of 0 as well" {
			# Open-ProjectTerminals passes its caller window as -WindowId "0".
			Open-Terminal -Command "echo test" -WindowId "0"

			Should -Invoke Set-WindowForeground -Times 1 -Exactly
		}

		It "leaves the windows alone when its own window is only a guess" {
			Mock Resolve-HostingTerminalTab { [PSCustomObject]@{ Handle = [IntPtr]4242; ProcessId = 1; TabTitle = 'PowerShell'; Exact = $false } }

			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Set-WindowForeground -Times 0
			Should -Invoke Start-Process -Times 1 -ParameterFilter { $ArgumentList -contains "0" }
		}

		It "still opens the tabs when the shell is not hosted by Windows Terminal" {
			Mock Resolve-HostingTerminalTab { $null }

			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Set-WindowForeground -Times 0
			Should -Invoke Start-Process -Times 1
		}

		It "does not look for its window when the target window is named" {
			$env:WT_WINDOW_ID = "caller-window-guid"

			Open-Terminal -Command "echo test" -InSameShell
			Open-Terminal -Command "echo test" -WindowId "explicit-id"
			Open-Terminal -Command "echo test"

			Should -Invoke Resolve-HostingTerminalTab -Times 0
		}

		It "does not activate a window for an elevated spawn" {
			Open-Terminal -Command "echo test" -InSameShell -Administrator

			Should -Invoke Resolve-HostingTerminalTab -Times 0
		}
	}
}

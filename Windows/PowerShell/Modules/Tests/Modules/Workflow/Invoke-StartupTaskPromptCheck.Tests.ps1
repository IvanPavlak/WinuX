#Requires -Modules Pester

BeforeAll {
	$script:SavedState = $global:WinuXStartupTaskPrompt
	$script:SavedExitCode = $global:LASTEXITCODE

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTaskPromptCheck.ps1"
	# Dot-sourced so they exist to Mock whatever the session's imported modules hold.
	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTasks.ps1"
	. "$ModuleRoot\Workflow\Functions\Register-StartupTaskPromptCheck.ps1"
}

AfterAll {
	$global:WinuXStartupTaskPrompt = $script:SavedState
	$global:LASTEXITCODE = $script:SavedExitCode
}

Describe "Invoke-StartupTaskPromptCheck" {
	BeforeEach {
		$global:WinuXStartupTaskPrompt = [pscustomobject]@{
			Original  = { "original> " }
			NextCheck = (Get-Date).AddHours(1)
		}

		Mock Invoke-StartupTasks { }
		# The real one works the next day start out from the configuration; here it only has to
		# be asked. The boundary this function sets itself is what the tests below look at.
		Mock Register-StartupTaskPromptCheck { }
	}

	Context "before the next day starts" {
		It "returns the original prompt's text and runs nothing" {
			Invoke-StartupTaskPromptCheck | Should -Be "original> "

			Should -Invoke Invoke-StartupTasks -Times 0 -Exactly
			Should -Invoke Register-StartupTaskPromptCheck -Times 0 -Exactly
		}

		It "leaves the boundary where it is" {
			$boundary = $global:WinuXStartupTaskPrompt.NextCheck

			Invoke-StartupTaskPromptCheck | Out-Null

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be $boundary
		}

		It "hands the original prompt the last command's failure" {
			$global:WinuXStartupTaskPrompt.Original = { "status=$?" }

			Get-Item -LiteralPath (Join-Path $TestDrive "missing") -ErrorAction SilentlyContinue
			$text = Invoke-StartupTaskPromptCheck

			$text | Should -Be "status=False"
		}

		It "returns only the prompt text" {
			$text = Invoke-StartupTaskPromptCheck

			@($text).Count | Should -Be 1
			$text | Should -BeOfType [string]
		}
	}

	Context "once the next day has started" {
		BeforeEach {
			$global:WinuXStartupTaskPrompt.NextCheck = (Get-Date).AddMinutes(-1)
		}

		It "runs the TerminalOpen tasks and still returns the original prompt's text" {
			Invoke-StartupTaskPromptCheck | Should -Be "original> "

			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly -ParameterFilter { $Trigger -eq 'TerminalOpen' }
		}

		It "asks for every task, and for no prompt redraw: the text is returned below their output anyway" {
			Invoke-StartupTaskPromptCheck | Out-Null

			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly -ParameterFilter {
				-not $RedrawPrompt -and -not $PesterBoundParameters.ContainsKey('Name') -and -not $PesterBoundParameters.ContainsKey('WhatIf')
			}
		}

		It "returns only the prompt text after a run" {
			$text = Invoke-StartupTaskPromptCheck

			@($text).Count | Should -Be 1
			$text | Should -Be "original> "
		}

		It "runs the tasks once, then waits for the day after" {
			Invoke-StartupTaskPromptCheck | Out-Null
			Invoke-StartupTaskPromptCheck | Out-Null
			Invoke-StartupTaskPromptCheck | Out-Null

			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
			$global:WinuXStartupTaskPrompt.NextCheck | Should -BeGreaterThan (Get-Date)
		}

		It "has Register-StartupTaskPromptCheck work out the next boundary after the run" {
			$script:Sequence = [System.Collections.Generic.List[string]]::new()
			Mock Invoke-StartupTasks { $script:Sequence.Add('run') }
			Mock Register-StartupTaskPromptCheck { $script:Sequence.Add('register') }

			Invoke-StartupTaskPromptCheck | Out-Null

			($script:Sequence -join ',') | Should -Be 'run,register'
		}

		It "moves the boundary on before the run, so a second prompt during it does not run the tasks again" {
			Mock Invoke-StartupTasks { $script:BoundaryDuringRun = $global:WinuXStartupTaskPrompt.NextCheck }

			Invoke-StartupTaskPromptCheck | Out-Null

			$script:BoundaryDuringRun | Should -BeGreaterThan (Get-Date)
		}

		It "runs the original prompt first, before any task" {
			$script:Sequence = [System.Collections.Generic.List[string]]::new()
			$global:WinuXStartupTaskPrompt.Original = { $script:Sequence.Add('prompt'); "original> " }
			Mock Invoke-StartupTasks { $script:Sequence.Add('run') }

			Invoke-StartupTaskPromptCheck | Should -Be "original> "

			($script:Sequence -join ',') | Should -Be 'prompt,run'
		}

		It "keeps the exit code of the user's last command" {
			Mock Invoke-StartupTasks { $global:LASTEXITCODE = 128 }
			$global:LASTEXITCODE = 3

			Invoke-StartupTaskPromptCheck | Out-Null

			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
			$global:LASTEXITCODE | Should -Be 3
		}

		It "keeps the exit code of the user's last command when the run throws" {
			Mock Invoke-StartupTasks { $global:LASTEXITCODE = 128; throw "network down" }
			$global:LASTEXITCODE = 3

			Invoke-StartupTaskPromptCheck | Out-Null

			$global:LASTEXITCODE | Should -Be 3
		}

		It "still returns the prompt and moves the boundary on when the run throws" {
			Mock Invoke-StartupTasks { throw "network down" }
			$script:Text = $null

			{ $script:Text = Invoke-StartupTaskPromptCheck } | Should -Not -Throw

			$script:Text | Should -Be "original> "
			$global:WinuXStartupTaskPrompt.NextCheck | Should -BeGreaterThan (Get-Date)
			Should -Invoke Register-StartupTaskPromptCheck -Times 1 -Exactly
		}

		It "does not try a run that throws again at the next prompt" {
			Mock Invoke-StartupTasks { throw "network down" }

			Invoke-StartupTaskPromptCheck | Out-Null
			Invoke-StartupTaskPromptCheck | Out-Null

			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
		}

		It "still returns the prompt when working out the next boundary throws" {
			Mock Register-StartupTaskPromptCheck { throw "broken configuration" }
			$script:Text = $null

			{ $script:Text = Invoke-StartupTaskPromptCheck } | Should -Not -Throw

			$script:Text | Should -Be "original> "
			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
			$global:WinuXStartupTaskPrompt.NextCheck | Should -BeGreaterThan (Get-Date)
		}

		It "runs the tasks even when the original prompt throws, and returns the default prompt" {
			$global:WinuXStartupTaskPrompt.Original = { throw "theme not found" }
			$script:Text = $null

			{ $script:Text = Invoke-StartupTaskPromptCheck } | Should -Not -Throw

			$script:Text | Should -BeLike "PS *> "
			Should -Invoke Invoke-StartupTasks -Times 1 -Exactly
		}
	}

	Context "without the recorded original prompt" {
		It "falls back to the default prompt and runs nothing" {
			$global:WinuXStartupTaskPrompt = $null
			$script:Text = $null

			{ $script:Text = Invoke-StartupTaskPromptCheck } | Should -Not -Throw

			$script:Text | Should -BeLike "PS *> "
			Should -Invoke Invoke-StartupTasks -Times 0 -Exactly
		}

		It "falls back to the default prompt when the state holds no prompt" {
			$global:WinuXStartupTaskPrompt = [pscustomobject]@{ Original = $null; NextCheck = (Get-Date).AddHours(1) }

			Invoke-StartupTaskPromptCheck | Should -BeLike "PS *> "
		}
	}
}

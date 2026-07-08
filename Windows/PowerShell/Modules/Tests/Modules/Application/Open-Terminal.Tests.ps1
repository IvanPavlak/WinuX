#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	. "$FunctionsPath\Open-Terminal.ps1"
}

Describe "Open-Terminal" {
	BeforeEach {
		Mock Start-Process { }
		Mock Start-Sleep { }
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

	Context "When InSameShell is specified without WindowId" {
		It "Should use window ID 0" {
			Open-Terminal -Command "echo test" -InSameShell

			Should -Invoke Start-Process -Times 1 -ParameterFilter {
				$ArgumentList -contains "0"
			}
		}
	}
}

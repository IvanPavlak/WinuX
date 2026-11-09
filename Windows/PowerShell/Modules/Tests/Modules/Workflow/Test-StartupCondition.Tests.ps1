#Requires -Modules Pester

BeforeAll {
	$script:SavedConfiguration = $global:Configuration
	$script:SavedExitCode = $global:LASTEXITCODE

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Test-StartupCondition.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	$global:LASTEXITCODE = $script:SavedExitCode
}

Describe "Test-StartupCondition" {
	BeforeEach {
		$global:Configuration = @{}
		# Counted by the condition's own Test text, so a test can say how often it ran.
		$script:ConditionCalls = 0

		Mock Write-LogError { }
		Mock Write-LogStep { }
		Mock Start-Sleep { }
	}

	Context "what counts as met" {
		It "is met when the test outputs <Label>" -ForEach @(
			@{ Label = 'true'; Test = '$true' }
			@{ Label = 'a non-empty string'; Test = "'connected'" }
			@{ Label = 'a number other than 0'; Test = '1' }
			@{ Label = 'an object'; Test = '[pscustomobject]@{ State = "Up" }' }
		) {
			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = $Test; Timeout = 0 } } | Should -BeTrue
		}

		It "is not met when the test <Label>" -ForEach @(
			@{ Label = 'outputs false'; Test = '$false' }
			@{ Label = 'outputs an empty string'; Test = "''" }
			@{ Label = 'outputs 0'; Test = '0' }
			@{ Label = 'outputs null'; Test = '$null' }
			@{ Label = 'outputs nothing'; Test = 'if ($false) { "never" }' }
			@{ Label = 'throws'; Test = 'throw "the service is down"' }
			@{ Label = 'names a command that does not exist'; Test = 'Get-NoSuchStartupConditionCommand' }
		) {
			$script:Result = $null

			{ $script:Result = Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = $Test; Timeout = 0 } } } | Should -Not -Throw

			$script:Result | Should -BeFalse
		}

		It "returns a boolean, not what the test printed" {
			$result = Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = "'connected'"; Timeout = 0 } }

			$result | Should -BeOfType [bool]
			@($result).Count | Should -Be 1
		}
	}

	Context "a definition that cannot be used" {
		It "is not met, and does not throw, when <Case>" -ForEach @(
			@{ Case = 'the name has no entry'; Definitions = @{ Other = @{ Test = '$true' } } }
			@{ Case = 'there are no conditions at all'; Definitions = @{} }
			@{ Case = 'the entry is not a hashtable'; Definitions = @{ MyCondition = '$true' } }
			@{ Case = 'the entry has no Test'; Definitions = @{ MyCondition = @{ Timeout = 5 } } }
			@{ Case = 'the Test is blank'; Definitions = @{ MyCondition = @{ Test = '   ' } } }
			@{ Case = 'the Test does not parse'; Definitions = @{ MyCondition = @{ Test = 'if (' } } }
		) {
			$script:Result = $null

			{ $script:Result = Test-StartupCondition -Name MyCondition -Definitions $Definitions } | Should -Not -Throw

			$script:Result | Should -BeFalse
			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Start-Sleep -Times 0 -Exactly
		}
	}

	Context "where the condition is looked up" {
		It "finds the name whatever its casing" {
			Test-StartupCondition -Name myvpn -Definitions @{ MyVpn = @{ Test = '$true'; Timeout = 0 } } | Should -BeTrue
		}

		It "reads Startup.Conditions of the configuration without -Definitions" {
			$global:Configuration = @{ Startup = @{ Conditions = @{ Network = @{ Test = '$true'; Timeout = 0 } } } }

			Test-StartupCondition -Name Network | Should -BeTrue
		}

		It "is not met for any name when the configuration has no Startup section" {
			Test-StartupCondition -Name Network | Should -BeFalse

			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "takes -Definitions over the configuration" {
			$global:Configuration = @{ Startup = @{ Conditions = @{ Network = @{ Test = '$false'; Timeout = 0 } } } }

			Test-StartupCondition -Name Network -Definitions @{ Network = @{ Test = '$true'; Timeout = 0 } } | Should -BeTrue
		}

		It "does not fall back to the configuration for a name -Definitions lacks" {
			$global:Configuration = @{ Startup = @{ Conditions = @{ Network = @{ Test = '$true'; Timeout = 0 } } } }

			Test-StartupCondition -Name Network -Definitions @{ MyVpn = @{ Test = '$true' } } | Should -BeFalse
		}
	}

	Context "how often the test runs" {
		It "tests exactly once with -NoWait, whatever the timeout" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $false'; Timeout = 600; Interval = 1 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions -NoWait | Should -BeFalse

			$script:ConditionCalls | Should -Be 1
			Should -Invoke Start-Sleep -Times 0 -Exactly
			Should -Invoke Write-LogStep -Times 0 -Exactly
		}

		It "tests exactly once with a timeout of 0" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $false'; Timeout = 0 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeFalse

			$script:ConditionCalls | Should -Be 1
			Should -Invoke Start-Sleep -Times 0 -Exactly
		}

		It "returns at once, without waiting, when the first test is met" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $true'; Timeout = 600 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeTrue

			$script:ConditionCalls | Should -Be 1
			Should -Invoke Start-Sleep -Times 0 -Exactly
			Should -Invoke Write-LogStep -Times 0 -Exactly
		}

		It "tests again every interval until the condition is met" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $script:ConditionCalls -ge 3'; Timeout = 600; Interval = 1 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeTrue

			$script:ConditionCalls | Should -Be 3
			Should -Invoke Start-Sleep -Times 2 -Exactly
			Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Milliseconds -eq 1000 }
		}

		It "says once that it is waiting, however long it waits" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $script:ConditionCalls -ge 5'; Timeout = 600; Interval = 1 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeTrue

			Should -Invoke Write-LogStep -Times 1 -Exactly
		}

		It "waits half a second between tests with an interval of 0.5" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $script:ConditionCalls -ge 2'; Timeout = 600; Interval = 0.5 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeTrue

			Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 500 }
		}

		It "waits two seconds between tests when the interval is <Label>" -ForEach @(
			@{ Label = 'absent'; Entry = @{ Timeout = 600 } }
			@{ Label = '0'; Entry = @{ Timeout = 600; Interval = 0 } }
			@{ Label = 'negative'; Entry = @{ Timeout = 600; Interval = -3 } }
			@{ Label = 'not a number'; Entry = @{ Timeout = 600; Interval = 'often' } }
		) {
			$Entry.Test = '$script:ConditionCalls++; $script:ConditionCalls -ge 2'

			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = $Entry } | Should -BeTrue

			Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 2000 }
		}
	}

	Context "when the timeout passes" {
		BeforeEach {
			# A clock only the mocked sleep moves: the timeout passes without any real wait.
			$script:Clock = [datetime]::new(2026, 3, 10, 12, 0, 0)
			Mock Get-Date { $script:Clock }
			Mock Start-Sleep { $script:Clock = $script:Clock.AddMilliseconds($Milliseconds) }
		}

		It "gives up once the timeout has passed, after one last test" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $false'; Timeout = 5; Interval = 2 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeFalse

			# Tested at 0, 2, 4 and 6 seconds: the test at 6 s is the first one past the timeout.
			$script:ConditionCalls | Should -Be 4
			Should -Invoke Start-Sleep -Times 3 -Exactly
		}

		It "is met by a test that succeeds right at the timeout" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $script:ConditionCalls -ge 4'; Timeout = 6; Interval = 2 } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeTrue

			$script:ConditionCalls | Should -Be 4
		}

		It "waits 60 seconds when the timeout is <Label>" -ForEach @(
			@{ Label = 'absent'; Entry = @{ Interval = 30 } }
			@{ Label = 'negative'; Entry = @{ Interval = 30; Timeout = -5 } }
			@{ Label = 'not a number'; Entry = @{ Interval = 30; Timeout = 'soon' } }
		) {
			$Entry.Test = '$script:ConditionCalls++; $false'

			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = $Entry } | Should -BeFalse

			# Tested at 0, 30 and 60 seconds.
			$script:ConditionCalls | Should -Be 3
		}

		It "takes a timeout written as text" {
			$definitions = @{ MyCondition = @{ Test = '$script:ConditionCalls++; $false'; Timeout = '4'; Interval = '2' } }

			Test-StartupCondition -Name MyCondition -Definitions $definitions | Should -BeFalse

			# Tested at 0, 2 and 4 seconds.
			$script:ConditionCalls | Should -Be 3
		}
	}

	Context "the caller's exit code" {
		It "is put back after a test that changed it and was met" {
			$global:LASTEXITCODE = 7

			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = '$global:LASTEXITCODE = 99; $true'; Timeout = 0 } } | Should -BeTrue

			$global:LASTEXITCODE | Should -Be 7
		}

		It "is put back after a test that changed it and was not met" {
			$global:LASTEXITCODE = 7

			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = '$global:LASTEXITCODE = 99; $LASTEXITCODE -eq 0'; Timeout = 0 } } | Should -BeFalse

			$global:LASTEXITCODE | Should -Be 7
		}

		It "is put back after a test that threw" {
			$global:LASTEXITCODE = 7

			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = '$global:LASTEXITCODE = 99; throw "down"'; Timeout = 0 } } | Should -BeFalse

			$global:LASTEXITCODE | Should -Be 7
		}

		It "answers a test that ends with the exit code of a program" {
			# What the documented `myvpn status *> $null; $LASTEXITCODE -eq 0` comes down to.
			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = '$global:LASTEXITCODE = 0; $LASTEXITCODE -eq 0'; Timeout = 0 } } | Should -BeTrue
			Test-StartupCondition -Name MyCondition -Definitions @{ MyCondition = @{ Test = '$global:LASTEXITCODE = 3; $LASTEXITCODE -eq 0'; Timeout = 0 } } | Should -BeFalse
		}
	}
}

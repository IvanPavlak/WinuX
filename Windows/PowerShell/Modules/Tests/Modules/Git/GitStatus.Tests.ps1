#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitStatus.ps1"
}

Describe "GitStatus" {
	BeforeEach {
		Mock git { }
	}

	Context "configured arguments" {
		It "passes the configured arguments to git status" {
			Mock Get-ConfigSetting { @('-sb', '--ignored') }

			GitStatus

			Should -Invoke git -Times 1 -ParameterFilter {
				$args.Count -eq 3 -and
				$args[0] -eq "status" -and
				$args[1] -eq "-sb" -and
				$args[2] -eq "--ignored"
			}
		}

		It "falls back to --short when the key is absent" {
			Mock Get-ConfigSetting { param($Path, $Default) $Default }

			GitStatus

			Should -Invoke git -Times 1 -ParameterFilter {
				$args.Count -eq 2 -and $args[0] -eq "status" -and $args[1] -eq "--short"
			}
		}

		It "runs a plain git status when the configured array is empty" {
			Mock Get-ConfigSetting { @() }

			GitStatus

			Should -Invoke git -Times 1 -ParameterFilter {
				$args.Count -eq 1 -and $args[0] -eq "status"
			}
		}
	}

	Context "explicit arguments" {
		It "replaces the configured arguments and does not read the configuration" {
			Mock Get-ConfigSetting { @('--short') }

			GitStatus -v -v -u

			Should -Invoke git -Times 1 -ParameterFilter {
				$args.Count -eq 4 -and
				$args[0] -eq "status" -and
				$args[1] -eq "-v" -and
				$args[2] -eq "-v" -and
				$args[3] -eq "-u"
			}
			Should -Invoke Get-ConfigSetting -Times 0
		}
	}
}

Describe "GitStatus with real git" -Tag 'Integration' {
	# The Describe above mocks git, so it cannot see how PowerShell hands an array to the real
	# executable. A one-element array that got unrolled into a string reached git as no
	# argument at all and the long format came back; only a real git run shows the difference.
	BeforeAll {
		$repository = Join-Path $TestDrive "status-repo"
		New-Item -ItemType Directory -Path $repository -Force | Out-Null
		& git -C $repository init --quiet
		Set-Content -Path (Join-Path $repository "untracked.txt") -Value "x"
	}

	BeforeEach {
		Push-Location $repository
	}

	AfterEach {
		Pop-Location
	}

	It "prints the short format when the configured array holds one element" {
		Mock Get-ConfigSetting { @('--short') }

		$output = GitStatus | Out-String

		$output | Should -Match '\?\? untracked\.txt'
		$output | Should -Not -Match 'On branch'
	}

	It "prints the long format for an empty configured array" {
		Mock Get-ConfigSetting { @() }

		$output = GitStatus | Out-String

		$output | Should -Match 'On branch'
		$output | Should -Match 'untracked\.txt'
	}

	It "uses the explicit arguments instead of the configured ones" {
		Mock Get-ConfigSetting { @('--short') }

		$output = GitStatus --branch --short | Out-String

		$output | Should -Match '## '
	}
}

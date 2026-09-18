#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Resolve-RepositoryTargets.ps1"
	# Resolved for real rather than mocked: the whole point of the resolver is that URL and
	# path resolution stay in one place, so the tests exercise that place.
	. "$ModuleRoot\Helper\Functions\Resolve-ProjectPath.ps1"
}

Describe "Resolve-RepositoryTargets" {
	BeforeEach {
		# Three groups, five repositories. "Mike" is listed in both Beta and Gamma, so it also
		# covers the duplicate case. Names inside Alpha are deliberately out of alphabetical
		# order, so a stray Sort-Object would show up immediately.
		$global:Configuration = @{
			Universal        = @{
				GitHub = @{
					Base    = "https://github.com/"
					Private = @{
						Zulu  = "acme/Zulu"
						Alfa  = "acme/Alfa"
						Mike  = "acme/Mike"
						Bravo = "acme/Bravo"
						Golf  = "acme/Golf"
					}
				}
			}
			RepositoryGroups = @(
				@{ Alpha = @(
						@{ Name = "Zulu"; UrlPath = "Universal.GitHub.Private.Zulu"; LocalPath = "Repos.Zulu" }
						@{ Name = "Alfa"; UrlPath = "Universal.GitHub.Private.Alfa"; LocalPath = "Repos.Alfa" }
					)
				}
				@{ Beta = @(
						@{ Name = "Mike"; UrlPath = "Universal.GitHub.Private.Mike"; LocalPath = "Repos.Mike" }
						@{ Name = "Bravo"; UrlPath = "Universal.GitHub.Private.Bravo"; LocalPath = "Repos.Bravo" }
					)
				}
				@{ Gamma = @(
						@{ Name = "Mike"; UrlPath = "Universal.GitHub.Private.Mike"; LocalPath = "Repos.Mike" }
						@{ Name = "Golf"; UrlPath = "Universal.GitHub.Private.Golf"; LocalPath = "Repos.Golf" }
					)
				}
			)
		}

		$script:MachineSpecificPaths = @{
			Repos = @{
				Zulu  = "C:\Repos\Zulu"
				Alfa  = "C:\Repos\Alfa"
				Mike  = "C:\Repos\Mike"
				Bravo = "C:\Repos\Bravo"
				Golf  = "C:\Repos\Golf"
			}
		}

		Mock Write-LogError { }
	}

	It "Should expand -All in configuration order, not alphabetically" {
		$targets = Resolve-RepositoryTargets -All

		@($targets).Name -join "," | Should -Be "Zulu,Alfa,Mike,Bravo,Golf"
		@($targets).Group -join "," | Should -Be "Alpha,Alpha,Beta,Beta,Gamma"
	}

	It "Should resolve the real URL and local path for each target" {
		$targets = Resolve-RepositoryTargets -All
		$target = $targets[0]

		$target.RepositoryUrl | Should -Be "https://github.com/acme/Zulu"
		$target.LocalPath | Should -Be "C:\Repos\Zulu"
	}

	It "Should expand a single group in configuration order" {
		$targets = Resolve-RepositoryTargets -Group Beta

		@($targets).Name -join "," | Should -Be "Mike,Bravo"
	}

	It "Should match a group name case-insensitively and report the configured spelling" {
		$targets = Resolve-RepositoryTargets -Group "gamma"

		@($targets).Name -join "," | Should -Be "Mike,Golf"
		@($targets).Group | Select-Object -Unique | Should -Be "Gamma"
	}

	It "Should expand several groups in the requested order" {
		$targets = Resolve-RepositoryTargets -Group Beta, Alpha

		@($targets).Name -join "," | Should -Be "Mike,Bravo,Zulu,Alfa"
	}

	It "Should list a repository shared by two groups only once" {
		$targets = Resolve-RepositoryTargets -Group Beta, Gamma

		@($targets).Name -join "," | Should -Be "Mike,Bravo,Golf"
	}

	It "Should reject an unknown group without resolving anything" {
		Mock Resolve-ProjectPath { }

		$targets = Resolve-RepositoryTargets -Group "Wrok", "Beta"

		$targets | Should -BeNullOrEmpty
		Should -Invoke Resolve-ProjectPath -Times 0
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter {
			$Message -match "Wrok" -and $Message -match "Alpha" -and $Message -match "Beta" -and $Message -match "Gamma"
		}
	}

	It "Should return an empty array rather than a null when a known group is empty" {
		$global:Configuration.RepositoryGroups = @(@{ Alpha = @() })

		$targets = Resolve-RepositoryTargets -Group Alpha

		# $null is reserved for "unknown group name" - an empty but valid group is an empty array.
		($null -ne $targets) | Should -BeTrue
		@($targets).Count | Should -Be 0
	}

	It "Should resolve repositories by name and report their owning group" {
		$targets = Resolve-RepositoryTargets -Repositories "Golf", "Alfa"

		@($targets).Name -join "," | Should -Be "Golf,Alfa"
		@($targets).Group -join "," | Should -Be "Gamma,Alpha"
	}

	It "Should skip null and whitespace repository names" {
		Mock Resolve-ProjectPath { [PSCustomObject]@{ RepositoryUrl = "u"; LocalPath = $ProjectName } }

		$targets = Resolve-RepositoryTargets -Repositories @("Golf", "", "   ", $null)

		@($targets).Count | Should -Be 1
		Should -Invoke Resolve-ProjectPath -Times 1 -Exactly
	}
}

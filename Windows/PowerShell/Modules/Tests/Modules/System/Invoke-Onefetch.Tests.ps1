#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Invoke-Onefetch.ps1"
	. "$FunctionsPath\Resolve-TerminalGreetingSettings.ps1"
	. "$ModuleRoot\Git\Functions\Test-GitRepository.ps1"

	# onefetch is an external binary absent on CI runners; stub it so Mock can attach
	# (no-op where onefetch is installed).
	if (-not (Get-Command onefetch -ErrorAction SilentlyContinue)) {
		function onefetch { }
	}

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) {
		function Write-LogWarning { param([string]$Message) }
	}
}

Describe "Invoke-Onefetch" {
	BeforeEach {
		Mock onefetch { }
		Mock Write-LogDebug { }

		# The real binary sets this; a mocked function does not, so it is pinned to "succeeded"
		# and the empty-repository test overrides it.
		$global:LASTEXITCODE = 0

		$script:SavedConfiguration = $global:Configuration
		# Enabled, so every test states its own reason for a no-op rather than inheriting one.
		$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true } } }

		# A directory that IS a repository, and one that is not.
		$script:Repo = Join-Path $TestDrive "repo"
		$script:NotRepo = Join-Path $TestDrive "plain"
		New-Item -ItemType Directory -Path (Join-Path $script:Repo ".git") -Force | Out-Null
		New-Item -ItemType Directory -Path $script:NotRepo -Force | Out-Null
	}

	AfterEach { $global:Configuration = $script:SavedConfiguration }

	Context "the three reasons to do nothing" {
		It "does nothing when TerminalGreeting.Onefetch.Enabled is false" {
			# The shipped default. Nothing printed, nothing run, one debug line.
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $false } } }

			Invoke-Onefetch -Path $script:Repo | Should -BeNullOrEmpty

			Should -Invoke onefetch -Times 0 -Exactly
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*Enabled is false*" }
		}

		It "does nothing when the onefetch binary is not installed" {
			Mock Get-Command { $null } -ParameterFilter { $Name -eq "onefetch" }

			Invoke-Onefetch -Path $script:Repo | Should -BeNullOrEmpty

			Should -Invoke onefetch -Times 0 -Exactly
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*not installed*" }
		}

		It "does nothing outside a git repository" {
			# The common case: `c` in an ordinary directory must print a system info panel and
			# nothing else, with no error.
			Invoke-Onefetch -Path $script:NotRepo | Should -BeNullOrEmpty

			Should -Invoke onefetch -Times 0 -Exactly
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*not inside a git repository*" }
		}

		It "throws in none of the three cases" {
			$global:Configuration = @{}

			{ Invoke-Onefetch -Path $script:NotRepo } | Should -Not -Throw
		}
	}

	Context "inside a repository" {
		It "runs onefetch once" {
			Invoke-Onefetch -Path $script:Repo

			Should -Invoke onefetch -Times 1 -Exactly
		}

		It "finds the repository from a directory below its root" {
			$nested = Join-Path $script:Repo "src\deep"
			New-Item -ItemType Directory -Path $nested -Force | Out-Null

			Invoke-Onefetch -Path $nested

			Should -Invoke onefetch -Times 1 -Exactly
		}

		It "logs the exit code and prints nothing extra when onefetch fails on an empty repository" {
			Mock onefetch { $global:LASTEXITCODE = 1 }

			{ Invoke-Onefetch -Path $script:Repo } | Should -Not -Throw
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*exited 1*" }
		}
	}

	Context "the Arguments passthrough" {
		It "forwards the configured arguments to the binary" {
			$script:Captured = $null
			Mock onefetch { $script:Captured = $args }
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true; Arguments = @("--no-art", "--no-merges") } } }

			Invoke-Onefetch -Path $script:Repo

			$script:Captured | Should -Be @("--no-art", "--no-merges")
		}

		It "lets an explicit -Arguments beat the configured ones for one call" {
			$script:Captured = $null
			Mock onefetch { $script:Captured = $args }
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true; Arguments = @("--no-art") } } }

			Invoke-Onefetch -Path $script:Repo -Arguments "--no-merges"

			$script:Captured | Should -Be @("--no-merges")
		}

		It "passes nothing when nothing is configured" {
			$script:Captured = "not set"
			Mock onefetch { $script:Captured = $args }

			Invoke-Onefetch -Path $script:Repo

			$script:Captured.Count | Should -Be 0
		}
	}

	Context "-Measure" {
		It "returns the captured row count" {
			Mock onefetch { "row one"; "row two"; "row three" }

			Invoke-Onefetch -Path $script:Repo -Measure | Should -Be 3
		}

		It "returns 0 when onefetch is disabled" {
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $false } } }

			Invoke-Onefetch -Path $script:Repo -Measure | Should -Be 0
		}

		It "returns 0 outside a repository" {
			Invoke-Onefetch -Path $script:NotRepo -Measure | Should -Be 0
		}

		It "returns 0 when the binary is missing" {
			Mock Get-Command { $null } -ParameterFilter { $Name -eq "onefetch" }

			Invoke-Onefetch -Path $script:Repo -Measure | Should -Be 0
		}

		It "returns 0 rather than a partial count when onefetch exits non-zero" {
			# An empty repository writes a line or two to stderr and exits non-zero; counting that
			# as panel height would shrink the font for a panel that is never drawn.
			Mock onefetch { $global:LASTEXITCODE = 1; "error: no commits" }

			Invoke-Onefetch -Path $script:Repo -Measure | Should -Be 0
		}
	}

	Context "the passed settings" {
		It "uses the settings it is given instead of resolving again" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Enabled = $false } }
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true } } }

			Invoke-Onefetch -Path $script:Repo -Settings $settings

			Should -Invoke onefetch -Times 0 -Exactly
		}

		It "resolves for itself when none are passed, so it is usable on its own" {
			Invoke-Onefetch -Path $script:Repo

			Should -Invoke onefetch -Times 1 -Exactly
		}
	}
}

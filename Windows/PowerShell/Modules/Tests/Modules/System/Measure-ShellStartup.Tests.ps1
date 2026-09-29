#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Measure-ShellStartup.ps1")
	. (Join-Path $ModuleRoot "System\Functions\Invoke-ShellStartupSample.ps1")

	if (-not (Get-Module -Name Logging)) {
		function Write-LogTitle { param($Message) }
		function Write-LogStep { param($Message, [switch]$NoLeadingNewline) }
		function Write-LogWarning { param($Message) }
	}
}

Describe "Measure-ShellStartup" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }

		# Every launch is recorded; the wall time is a deterministic function of what is skipped,
		# so the medians and deltas can be asserted exactly. A bare start costs 200; Core 400; each
		# guarded stage adds 100 unless it is skipped. The in-shell trace reports 90 per stage that
		# ran (the 10 missing per stage is the harness's own overhead, as in reality).
		$script:launches = [System.Collections.Generic.List[object]]::new()
		Mock Invoke-ShellStartupSample {
			$script:launches.Add([pscustomobject]@{ Skip = $Skip; Bare = [bool]$Bare })
			if ($Bare) { return [pscustomobject]@{ Milliseconds = 200; Stages = @{} } }

			$skipped = @("$Skip" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
			$all = @("Schema", "Greeting", "OhMyPosh")
			$ran = if ($skipped -contains "All") { @() } else { @($all | Where-Object { $skipped -notcontains $_ }) }

			$stages = @{ Core = 390 }
			foreach ($name in $ran) { $stages[$name] = 90 }
			return [pscustomobject]@{ Milliseconds = 400 + 100 * $ran.Count; Stages = $stages }
		}

		$script:previousSession = $env:WT_SESSION
		$env:WT_SESSION = "test-session"
	}

	AfterEach {
		$env:WT_SESSION = $script:previousSession
	}

	Context "Cumulative mode" {
		It "walks bare, Core, then one added stage at a time, each configuration Runs times" {
			$rows = Measure-ShellStartup -Runs 2 -Stages Schema, Greeting, OhMyPosh -PassThru

			@($rows | ForEach-Object Configuration) | Should -Be @("bare (-NoProfile)", "Core", "+ Schema", "+ Greeting", "+ OhMyPosh")
			$script:launches.Count | Should -Be 10

			# The bare row launches with -NoProfile; Core skips everything; each later row skips
			# exactly the stages that come after the one it adds.
			$script:launches[0].Bare | Should -BeTrue
			$script:launches[2].Skip | Should -Be "All"
			$script:launches[4].Skip | Should -Be "Greeting,OhMyPosh"
			$script:launches[6].Skip | Should -Be "OhMyPosh"
			$script:launches[8].Skip | Should -Be ""
		}

		It "reports the delta to the previous row and the stage's own in-shell time" {
			$rows = @(Measure-ShellStartup -Runs 3 -Stages Schema, Greeting, OhMyPosh -PassThru)

			$rows[0].Median | Should -Be 200
			$rows[0].Delta | Should -BeNullOrEmpty
			$rows[1].Median | Should -Be 400
			$rows[1].Delta | Should -Be 200
			$rows[1].InShell | Should -Be 390
			$rows[2].Median | Should -Be 500
			$rows[2].Delta | Should -Be 100
			$rows[2].InShell | Should -Be 90
			$rows[3].Delta | Should -Be 100
		}

		It "records how many runs each row is based on" {
			$rows = @(Measure-ShellStartup -Runs 4 -Stages Schema -PassThru)

			@($rows | ForEach-Object Runs) | Should -Be @(4, 4, 4)
		}
	}

	Context "Isolated mode" {
		It "walks the full start, then the full start minus each stage" {
			$rows = @(Measure-ShellStartup -Mode Isolated -Runs 1 -Stages Schema, Greeting, OhMyPosh -PassThru)

			@($rows | ForEach-Object Configuration) | Should -Be @("full", "- Schema", "- Greeting", "- OhMyPosh")
			$script:launches[0].Skip | Should -Be ""
			$script:launches[1].Skip | Should -Be "Schema"
			$script:launches[3].Skip | Should -Be "OhMyPosh"
		}

		It "reports each stage's saving against the full start and its in-shell time from the full run" {
			$rows = @(Measure-ShellStartup -Mode Isolated -Runs 1 -Stages Schema, Greeting, OhMyPosh -PassThru)

			$rows[0].Median | Should -Be 700
			$rows[0].Delta | Should -BeNullOrEmpty
			$rows[1].Median | Should -Be 600
			$rows[1].Delta | Should -Be -100
			$rows[1].InShell | Should -Be 90
		}
	}

	Context "Medians" {
		It "takes the middle value of an odd sample count and the mean of the two middle values of an even one" {
			# The four wall times repeat for every configuration, so each row sees the same samples.
			$script:sequence = @(300, 100, 900, 200)
			$script:launchIndex = 0
			Mock Invoke-ShellStartupSample {
				$value = $script:sequence[$script:launchIndex % $script:sequence.Count]
				$script:launchIndex++
				return [pscustomobject]@{ Milliseconds = $value; Stages = @{} }
			}

			$rows = @(Measure-ShellStartup -Mode Isolated -Runs 4 -Stages Schema -PassThru | Select-Object -First 1)
			$rows[0].Median | Should -Be 250
			$rows[0].Min | Should -Be 100
			$rows[0].Max | Should -Be 900
		}
	}

	Context "Output" {
		It "returns nothing without -PassThru and prints the table instead" {
			$result = Measure-ShellStartup -Runs 1 -Stages Schema

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-LogStep -Times 3 -ParameterFilter { $Message -match "^\s+(bare|Core|\+ Schema)" }
		}

		It "warns when not running inside Windows Terminal" {
			$env:WT_SESSION = $null

			$null = Measure-ShellStartup -Runs 1 -Stages Schema

			Should -Invoke Write-LogWarning -Times 1
		}

		It "does not warn inside Windows Terminal" {
			$null = Measure-ShellStartup -Runs 1 -Stages Schema

			Should -Invoke Write-LogWarning -Times 0
		}
	}
}

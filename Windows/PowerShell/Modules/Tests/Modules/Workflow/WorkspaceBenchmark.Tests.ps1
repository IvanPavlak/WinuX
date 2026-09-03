#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Get-WorkspaceBenchmarkPath.ps1"
	. "$FunctionsPath\Write-WorkspaceBenchmark.ps1"
	. "$FunctionsPath\Get-WorkspaceBenchmark.ps1"

	# The path resolver reaches into the Logging module and the tracker path helper; stub both
	# commands when the modules are absent so the resolution tests can mock them either way.
	if (-not (Get-Command Get-LogPath -ErrorAction SilentlyContinue)) {
		function Get-LogPath { param([switch]$ErrorLog, [switch]$Directory) }
	}
	if (-not (Get-Command Get-WorkspaceStatePath -ErrorAction SilentlyContinue)) {
		function Get-WorkspaceStatePath { }
	}

	function New-LayoutTimings {
		param([hashtable]$Phases = @{}, [int]$Attempts = 1, [string]$Outcome = 'Applied')
		$ordered = [ordered]@{}
		foreach ($key in $Phases.Keys) { $ordered[$key] = $Phases[$key] }
		[PSCustomObject]@{
			Workspace    = 'MyWorkspace'
			Attempts     = $Attempts
			Outcome      = $Outcome
			TotalSeconds = 0
			Phases       = $ordered
			RecordedAt   = [DateTimeOffset]::Now
		}
	}
}

Describe "Write-WorkspaceBenchmark" {
	BeforeEach {
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		# One file per test - the rows a test writes must never be read by another.
		$script:BenchmarkFile = Join-Path $TestDrive ("Benchmark_" + [guid]::NewGuid().ToString('N') + ".csv")
	}

	It "creates the file with a header and appends one row per call" {
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 10 -BenchmarkPath $script:BenchmarkFile -Quiet
		Write-WorkspaceBenchmark -Workspace 'OtherWorkspace' -TotalSeconds 20 -BenchmarkPath $script:BenchmarkFile -Quiet

		$rows = @(Import-Csv -LiteralPath $script:BenchmarkFile)
		$rows.Count | Should -Be 2
		$rows[0].Workspace | Should -Be 'MyWorkspace'
		$rows[1].Workspace | Should -Be 'OtherWorkspace'
		@($rows[0].PSObject.Properties.Name) | Should -Contain 'WaitSeconds'
		@($rows[0].PSObject.Properties.Name) | Should -Contain 'Actions'
	}

	It "separates the layout action from the launch actions and books the remainder as other" {
		$row = Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 27.5 -BenchmarkPath $script:BenchmarkFile -Quiet -PassThru -ActionTimings @(
			[PSCustomObject]@{ Action = 'Open-Project'; Seconds = 0.5 }
			[PSCustomObject]@{ Action = 'Open-Browser'; Seconds = 0.3 }
			[PSCustomObject]@{ Action = 'Set-WorkspaceWindowLayout'; Seconds = 25.0 }
		)

		$row.ActionsSeconds | Should -Be 0.8
		$row.LayoutSeconds | Should -Be 25
		$row.OtherSeconds | Should -Be 1.7
		$row.Actions | Should -Be 'Open-Project=0.5;Open-Browser=0.3;Set-WorkspaceWindowLayout=25'
	}

	It "copies the layout phases, attempts and outcome, and marks alongside opens" {
		$timings = New-LayoutTimings -Phases @{ Wait = 15.1; FancyZones = 3.8; Snap = 3.9 } -Attempts 2 -Outcome 'Applied'

		$row = Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 30 -LayoutTimings $timings -Alongside -BenchmarkPath $script:BenchmarkFile -Quiet -PassThru

		$row.Mode | Should -Be 'Alongside'
		$row.Attempts | Should -Be 2
		$row.Outcome | Should -Be 'Applied'
		$row.WaitSeconds | Should -Be 15.1
		$row.FancyZonesSeconds | Should -Be 3.8
		$row.SnapSeconds | Should -Be 3.9
		$row.PositionSeconds | Should -Be 0
	}

	It "records NoLayout with every phase at zero when no layout record is supplied" {
		$row = Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 3 -BenchmarkPath $script:BenchmarkFile -Quiet -PassThru

		$row.Mode | Should -Be 'Plain'
		$row.Outcome | Should -Be 'NoLayout'
		$row.Attempts | Should -Be 0
		$row.WaitSeconds | Should -Be 0
		$row.OtherSeconds | Should -Be 3
	}

	It "writes numbers culture-invariant so the file reads the same on a comma-decimal machine" {
		$originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
		try {
			[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('hr-HR')
			Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 27.5 -BenchmarkPath $script:BenchmarkFile -Quiet
		}
		finally {
			[System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
		}

		(Get-Content -LiteralPath $script:BenchmarkFile -Raw) | Should -Match '27\.5'
		(Get-Content -LiteralPath $script:BenchmarkFile -Raw) | Should -Not -Match '27,5'
	}

	It "prints the timing line unless -Quiet" {
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 5 -BenchmarkPath $script:BenchmarkFile
		Should -Invoke Write-LogStep -Times 1 -Exactly

		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 5 -BenchmarkPath $script:BenchmarkFile -Quiet
		Should -Invoke Write-LogStep -Times 1 -Exactly
	}

	It "warns instead of throwing when the row cannot be written" {
		# A directory where the file should be - Export-Csv cannot write into it.
		$blockedPath = Join-Path $TestDrive ("Blocked_" + [guid]::NewGuid().ToString('N'))
		New-Item -ItemType Directory -Path $blockedPath | Out-Null

		{ Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 5 -BenchmarkPath $blockedPath -Quiet } | Should -Not -Throw
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}
}

Describe "Get-WorkspaceBenchmark" {
	BeforeEach {
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		$script:BenchmarkFile = Join-Path $TestDrive ("Benchmark_" + [guid]::NewGuid().ToString('N') + ".csv")
	}

	It "warns and returns nothing when no run has been recorded" {
		$result = Get-WorkspaceBenchmark -BenchmarkPath $script:BenchmarkFile

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "returns typed rows oldest first and honours -Last" {
		foreach ($total in 10, 20, 30, 40) {
			Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds $total -BenchmarkPath $script:BenchmarkFile -Quiet
		}

		$rows = @(Get-WorkspaceBenchmark -BenchmarkPath $script:BenchmarkFile -Last 2)

		$rows.Count | Should -Be 2
		$rows[0].TotalSeconds | Should -BeOfType [double]
		$rows[0].TotalSeconds | Should -Be 30
		$rows[1].TotalSeconds | Should -Be 40
		$rows[1].Attempts | Should -BeOfType [int]
	}

	It "returns every row with -Last 0" {
		foreach ($total in 1..12) {
			Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds $total -BenchmarkPath $script:BenchmarkFile -Quiet
		}

		@(Get-WorkspaceBenchmark -BenchmarkPath $script:BenchmarkFile).Count | Should -Be 10
		@(Get-WorkspaceBenchmark -BenchmarkPath $script:BenchmarkFile -Last 0).Count | Should -Be 12
	}

	It "filters by workspace, case-insensitively" {
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 10 -BenchmarkPath $script:BenchmarkFile -Quiet
		Write-WorkspaceBenchmark -Workspace 'OtherWorkspace' -TotalSeconds 20 -BenchmarkPath $script:BenchmarkFile -Quiet
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 12 -BenchmarkPath $script:BenchmarkFile -Quiet

		$rows = @(Get-WorkspaceBenchmark -Workspace 'myworkspace' -BenchmarkPath $script:BenchmarkFile)

		$rows.Count | Should -Be 2
		@($rows.Workspace | Select-Object -Unique) | Should -Be @('MyWorkspace')
	}

	It "aggregates per workspace and mode with -Summary" {
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 20 -LayoutTimings (New-LayoutTimings -Phases @{ Wait = 10; Snap = 4 } -Attempts 2) -BenchmarkPath $script:BenchmarkFile -Quiet
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 30 -LayoutTimings (New-LayoutTimings -Phases @{ Wait = 20; Snap = 6 }) -BenchmarkPath $script:BenchmarkFile -Quiet
		Write-WorkspaceBenchmark -Workspace 'MyWorkspace' -TotalSeconds 5 -Alongside -LayoutTimings (New-LayoutTimings -Outcome 'Escalated') -BenchmarkPath $script:BenchmarkFile -Quiet

		$summary = @(Get-WorkspaceBenchmark -Summary -BenchmarkPath $script:BenchmarkFile)

		$summary.Count | Should -Be 2
		$plain = $summary | Where-Object { $_.Mode -eq 'Plain' }
		$plain.Runs | Should -Be 2
		$plain.AvgTotal | Should -Be 25
		$plain.MinTotal | Should -Be 20
		$plain.MaxTotal | Should -Be 30
		$plain.AvgWait | Should -Be 15
		$plain.AvgSnap | Should -Be 5
		$plain.Retries | Should -Be 1
		$plain.NotApplied | Should -Be 0

		$alongside = $summary | Where-Object { $_.Mode -eq 'Alongside' }
		$alongside.Runs | Should -Be 1
		$alongside.NotApplied | Should -Be 1
	}
}

Describe "Get-WorkspaceBenchmarkPath" {
	It "puts the file next to the session logs when the Logging module resolves a directory" {
		Mock Get-LogPath { 'C:\Users\You\Logs' }

		Get-WorkspaceBenchmarkPath | Should -Be 'C:\Users\You\Logs\WorkspaceBenchmark.csv'
		Should -Invoke Get-LogPath -Times 1 -Exactly -ParameterFilter { $Directory }
	}

	It "falls back to the Workflow State folder when the Logging module is not available" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-LogPath' }
		Mock Get-WorkspaceStatePath { 'C:\Repo\Modules\Workflow\State\OpenWorkspaces.txt' }

		Get-WorkspaceBenchmarkPath | Should -Be 'C:\Repo\Modules\Workflow\State\WorkspaceBenchmark.csv'
	}
}

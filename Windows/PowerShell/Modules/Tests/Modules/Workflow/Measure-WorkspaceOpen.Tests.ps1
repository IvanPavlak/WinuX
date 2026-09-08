#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Get-WorkspaceBenchmarkPath.ps1"
	. "$FunctionsPath\Write-WorkspaceBenchmark.ps1"
	. "$FunctionsPath\Read-WorkspaceBenchmark.ps1"
	. "$FunctionsPath\Get-WorkspaceOpenMeasurementPath.ps1"
	. "$FunctionsPath\ConvertTo-WorkspaceOpenSummary.ps1"
	. "$FunctionsPath\Measure-WorkspaceOpen.ps1"

	# Stub-before-mock: the commands the harness calls must exist for Mock to attach to them,
	# and none of the real ones may run - a real Open-Workspace or Kill-All would act on the
	# machine the tests run on.
	foreach ($name in @('Write-LogTitle', 'Write-LogStep', 'Write-LogWarning', 'Write-LogSuccess')) {
		if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
			Set-Item -Path "function:script:$name" -Value { param([string]$Message, [switch]$NoLeadingNewline, $Style) }
		}
	}
	if (-not (Get-Command Write-LogError -ErrorAction SilentlyContinue)) {
		function Write-LogError { param([string]$Message, [switch]$NoLeadingNewline) }
	}
	if (-not (Get-Command Get-LogPath -ErrorAction SilentlyContinue)) {
		function Get-LogPath { param([switch]$ErrorLog, [switch]$Directory) }
	}
	if (-not (Get-Command Get-WorkspaceStatePath -ErrorAction SilentlyContinue)) {
		function Get-WorkspaceStatePath { }
	}
	function Kill-All { param($Exclude, $Skip, $Include, [switch]$IncludeCurrent, [switch]$ReloadPowerShellProfile) }
	function Open-Workspace { param($Workspace, $Project, [switch]$Alongside, [Parameter(ValueFromRemainingArguments = $true)]$ExtraArgs) }
	# The pre-checks run on the actions that apply on this machine. Pass-through here; the scope
	# semantics themselves are Resolve-WorkspaceActions.Tests.ps1's business.
	function Resolve-WorkspaceActions { param($Actions, $Workspace, $MachineType, $LayoutMachineType, $Configuration) $Actions }

	function New-TestConfiguration {
		param([hashtable]$Overrides = @{})
		$configuration = @{
			WorkspaceActions      = @{
				WinuX   = @(
					@{ Action = 'Open-Project'; Parameters = @{ Project = 'WinuX' } }
					@{ Action = 'Set-WorkspaceWindowLayout' }
				)
				# The workspace WinuX ships: what a fresh install measures without defining anything.
				Example = @(
					@{ Action = 'Open-Browser'; Parameters = @{ NoMenu = $true; Instances = 3 } }
					@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'Example' } }
				)
				# An Open-Project action with no project of its own: a menu on every open.
				Picker  = @(
					@{ Action = 'Open-Project' }
					@{ Action = 'Set-WorkspaceWindowLayout' }
				)
				Exiter  = @(
					@{ Action = 'Open-Project' }
					@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
				)
			}
			FancyZonesApplyMethod = 'File'
		}
		foreach ($key in $Overrides.Keys) { $configuration[$key] = $Overrides[$key] }
		return $configuration
	}

	function New-LayoutTimings {
		param([hashtable]$Phases = @{}, [int]$Attempts = 1, [string]$Outcome = 'Applied')
		$ordered = [ordered]@{}
		foreach ($key in $Phases.Keys) { $ordered[$key] = $Phases[$key] }
		[PSCustomObject]@{
			Workspace    = 'WinuX'
			Attempts     = $Attempts
			Outcome      = $Outcome
			TotalSeconds = 0
			Phases       = $ordered
			RecordedAt   = [DateTimeOffset]::Now
		}
	}

	# What the mocked Open-Workspace does: note the configuration in effect and append the next
	# scripted benchmark row, exactly as the real open would through Write-WorkspaceBenchmark.
	function Invoke-ScriptedOpen {
		param([string]$Workspace)
		$script:Observed += , [PSCustomObject]@{
			ApplyMethod  = $script:Configuration['FancyZonesApplyMethod']
			Pipelining   = $script:Configuration['WorkspaceLayoutPipelining']
			PrepareEarly = $script:Configuration['WorkspaceLayoutPrepareEarly']
			Benchmark    = $script:Configuration['WorkspaceBenchmark']
		}
		$scripted = if ($script:ScriptedRows.Count -gt 0) { $script:ScriptedRows.Dequeue() } else { @{ Total = 10; Attempts = 1 } }
		if ($scripted.Skip) { return }
		if ($null -eq $scripted.Attempts) { $scripted.Attempts = 1 }
		if ($scripted.Throw) { throw "open exploded" }
		$phases = @{ FancyZones = 1; Wait = 2; Position = 1; Snap = 1; Verify = 0.5 }
		if ($scripted.Phases) { $phases = $scripted.Phases }
		# Exactly what Open-Workspace does: the configured Source goes on the row.
		Write-WorkspaceBenchmark -Workspace $Workspace -TotalSeconds $scripted.Total -BenchmarkPath $script:BenchmarkFile -Quiet `
			-Source ([string]$script:Configuration['WorkspaceBenchmark'].Source) `
			-ActionTimings @([PSCustomObject]@{ Action = 'Set-WorkspaceWindowLayout'; Seconds = ($scripted.Total - 1) }) `
			-LayoutTimings (New-LayoutTimings -Phases $phases -Attempts $scripted.Attempts)
	}
}

Describe "Measure-WorkspaceOpen" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Start-Sleep { }
		Mock Kill-All { }
		Mock Open-Workspace { Invoke-ScriptedOpen -Workspace $Workspace }
		Mock Get-WorkspaceBenchmarkPath { $script:BenchmarkFile }

		$unique = [guid]::NewGuid().ToString('N')
		$script:BenchmarkFile = Join-Path $TestDrive "Benchmark_$unique.csv"
		$script:ResultFile = Join-Path $TestDrive "Measurements_$unique.csv"
		$script:Configuration = New-TestConfiguration
		$script:Observed = @()
		$script:ScriptedRows = [System.Collections.Queue]::new()
	}

	Context "plan" {
		It "builds Baseline plus one variant per setting with only that setting flipped" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -DryRun -Configuration $script:Configuration)

			$plan.Count | Should -Be 4
			$plan.Variant | Should -Be @('Baseline', 'ApplyMethod=Hotkeys', 'Pipelining=Off', 'PrepareEarly=Off')
			$plan[0].Settings | Should -Be ''
			$plan[1].Settings | Should -Be 'ApplyMethod=Hotkeys'
		}

		It "flips against the configured value, not the shipped default" {
			$configuration = New-TestConfiguration -Overrides @{ FancyZonesApplyMethod = 'Hotkeys'; WorkspaceLayoutPipelining = $false }

			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -DryRun -Configuration $configuration -Setting FancyZonesApplyMethod, WorkspaceLayoutPipelining)

			$plan.Variant | Should -Be @('Baseline', 'ApplyMethod=File', 'Pipelining=On')
		}

		It "-FullFactorial runs every combination of the chosen settings" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -DryRun -FullFactorial -Setting FancyZonesApplyMethod, WorkspaceLayoutPipelining -Configuration $script:Configuration)

			$plan.Count | Should -Be 4
			@($plan.Variant | Sort-Object -Unique).Count | Should -Be 4
			$plan.Variant | Should -Contain 'ApplyMethod=Hotkeys Pipelining=Off'
			$plan.Variant | Should -Contain 'ApplyMethod=File Pipelining=On'
		}

		It "interleaves the variants round by round and puts warm-ups first" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 2 -WarmUp 1 -DryRun -Setting FancyZonesApplyMethod -Configuration $script:Configuration)

			$plan.Count | Should -Be 5
			$plan[0].Measured | Should -BeFalse
			$plan[0].Round | Should -Be 0
			@($plan | Select-Object -Skip 1 | ForEach-Object { "$($_.Variant)/$($_.Round)" }) | Should -Be @('Baseline/1', 'ApplyMethod=Hotkeys/1', 'Baseline/2', 'ApplyMethod=Hotkeys/2')
		}

		It "-Order Sequential runs every round of one variant before the next" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 2 -WarmUp 0 -DryRun -Order Sequential -Setting FancyZonesApplyMethod -Configuration $script:Configuration)

			@($plan | ForEach-Object { "$($_.Variant)/$($_.Round)" }) | Should -Be @('Baseline/1', 'Baseline/2', 'ApplyMethod=Hotkeys/1', 'ApplyMethod=Hotkeys/2')
		}

		It "-Order Shuffled with a seed keeps every variant once per round" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 3 -WarmUp 0 -DryRun -Order Shuffled -Seed 7 -Configuration $script:Configuration)

			foreach ($round in 1..3) {
				$inRound = @($plan | Where-Object Round -eq $round)
				$inRound.Count | Should -Be 4
				@($inRound.Variant | Sort-Object -Unique).Count | Should -Be 4
			}
		}

		It "names explicit variants from their Name key or their overrides" {
			$plan = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -DryRun -Configuration $script:Configuration -Variant @{ Name = 'Current' }, @{ WorkspaceLayoutPrepareEarly = $false; SomeDelay = 250 }, @{})

			$plan.Variant | Should -Be @('Current', 'PrepareEarly=Off SomeDelay=250', 'Variant 3')
		}

		It "-DryRun neither opens nor tears down nor changes the configuration" {
			$before = $script:Configuration.Clone()

			Measure-WorkspaceOpen -Workspace WinuX -DryRun -Configuration $script:Configuration | Out-Null

			Should -Invoke Open-Workspace -Times 0 -Exactly
			Should -Invoke Kill-All -Times 0 -Exactly
			$script:Configuration.ContainsKey('WorkspaceBenchmark') | Should -BeFalse
			$script:Configuration['FancyZonesApplyMethod'] | Should -Be $before['FancyZonesApplyMethod']
		}
	}

	Context "guards" {
		It "refuses an unknown workspace" {
			$result = Measure-WorkspaceOpen -Workspace Nope -Configuration $script:Configuration

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Open-Workspace -Times 0 -Exactly
		}

		It "refuses a workspace whose actions end the calling shell" {
			$result = Measure-WorkspaceOpen -Workspace Exiter -Configuration $script:Configuration

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Open-Workspace -Times 0 -Exactly
		}

		It "judges the shell-exiting check on the actions that apply on this machine" {
			# The exiting action is scoped to another machine: the resolver drops it, so the
			# experiment may run.
			Mock Resolve-WorkspaceActions {
				param($Actions, $Workspace, $MachineType, $LayoutMachineType, $Configuration)
				@($Actions | Where-Object { $_.Action -ne 'Terminate-WindowsTerminalTabs' })
			}

			Measure-WorkspaceOpen Exiter Asseto -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			Should -Invoke Write-LogError -Times 0 -Exactly
			Should -Invoke Resolve-WorkspaceActions -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'Exiter' -and $null -ne $Configuration }
			Should -Invoke Open-Workspace -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'Exiter' }
		}

		It "refuses a workspace whose every action is scoped to another machine" {
			Mock Resolve-WorkspaceActions { @() }

			$result = Measure-WorkspaceOpen -Workspace Example -Configuration $script:Configuration

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*no actions that apply*' }
			Should -Invoke Open-Workspace -Times 0 -Exactly
		}

		It "refuses a workspace whose Open-Project action has no project unless -Project supplies one" {
			$result = Measure-WorkspaceOpen -Workspace Picker -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Open-Workspace -Times 0 -Exactly

			Measure-WorkspaceOpen Picker Asseto -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Open-Workspace -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'Picker' -and (@($Project) -join ',') -eq 'Asseto' }
		}
	}

	Context "defaults" {
		It "measures the shipped Example workspace when no workspace is named" {
			$result = Measure-WorkspaceOpen -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			Should -Invoke Open-Workspace -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'Example' }
			$result.Runs[0].Workspace | Should -Be 'Example'
		}
	}

	Context "runs" {
		It "puts each variant's values in effect during its open and restores everything afterwards" {
			Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Setting FancyZonesApplyMethod, WorkspaceLayoutPipelining -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			$script:Observed.Count | Should -Be 3
			$script:Observed[0].ApplyMethod | Should -Be 'File'
			$script:Observed[0].Pipelining | Should -BeNullOrEmpty
			$script:Observed[1].ApplyMethod | Should -Be 'Hotkeys'
			$script:Observed[1].Pipelining | Should -BeNullOrEmpty
			$script:Observed[2].ApplyMethod | Should -Be 'File'
			$script:Observed[2].Pipelining | Should -BeFalse
			# Every open records without printing a table per open.
			$script:Observed | ForEach-Object { $_.Benchmark.Enabled | Should -BeTrue; $_.Benchmark.Display | Should -Be 'None' }

			$script:Configuration['FancyZonesApplyMethod'] | Should -Be 'File'
			$script:Configuration.ContainsKey('WorkspaceLayoutPipelining') | Should -BeFalse
			$script:Configuration.ContainsKey('WorkspaceBenchmark') | Should -BeFalse
		}

		It "keeps a pre-existing benchmark opt-in as it was" {
			$script:Configuration['WorkspaceBenchmark'] = @{ Enabled = $true; Display = 'Table'; Last = 3 }

			Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Setting FancyZonesApplyMethod -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			$script:Configuration['WorkspaceBenchmark'].Display | Should -Be 'Table'
			$script:Configuration['WorkspaceBenchmark'].Last | Should -Be 3
		}

		It "tears down and settles before every open, warm-ups included, and counts only measured runs" {
			$result = Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 2 -SettleSeconds 3 -Setting FancyZonesApplyMethod -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			Should -Invoke Kill-All -Times 4 -Exactly
			Should -Invoke Start-Sleep -Times 4 -Exactly -ParameterFilter { $Seconds -eq 3 }
			Should -Invoke Open-Workspace -Times 4 -Exactly
			$result.Runs.Count | Should -Be 4
			@($result.Runs | Where-Object { -not $_.Measured }).Count | Should -Be 2
			@($result.Summary).Count | Should -Be 2
			$result.Summary | ForEach-Object { $_.Runs | Should -Be 1 }
		}

		It "hands the project and the remaining arguments to every open, so no open shows a menu" {
			$result = Measure-WorkspaceOpen WinuX Asseto run -Runs 1 -WarmUp 1 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			Should -Invoke Open-Workspace -Times 2 -Exactly -ParameterFilter { $Workspace -eq 'WinuX' -and (@($Project) -join ',') -eq 'Asseto' -and (@($ExtraArgs) -join ',') -eq 'run' }
			$result.Runs | ForEach-Object { $_.Project | Should -Be 'Asseto' }
			(Import-Csv -LiteralPath $script:ResultFile)[0].Project | Should -Be 'Asseto'
		}

		It "opens without a project when none is given" {
			Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			Should -Invoke Open-Workspace -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'WinuX' -and -not $Project -and -not $ExtraArgs }
		}

		It "tags the benchmark rows it causes with its session so the everyday history can leave them out" {
			$result = Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 1 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			$benchmarkRows = @(Read-WorkspaceBenchmark -BenchmarkPath $script:BenchmarkFile)
			$benchmarkRows.Count | Should -Be 2
			$benchmarkRows | ForEach-Object { $_.Source | Should -Be "Measure-WorkspaceOpen $($result.Session)" }
			# The row it read back is the tagged one, not an older untagged row of the same workspace.
			$result.Runs[1].Outcome | Should -Be 'Applied'
		}

		It "stops starting opens once -MaxMinutes is spent and still summarizes what ran" {
			$result = Measure-WorkspaceOpen -Workspace WinuX -Runs 3 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -MaxMinutes 0.005 -Teardown { [System.Threading.Thread]::Sleep(400) } -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			Should -Invoke Open-Workspace -Times 1 -Exactly
			$result.Runs.Count | Should -Be 1
			$result.Summary.Count | Should -Be 1
			$result.Summary[0].Runs | Should -Be 1
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like '*budget*' }
			$script:Configuration.ContainsKey('WorkspaceBenchmark') | Should -BeFalse
		}

		It "judges every variant against the first one: Noise inside the spread, Faster or Slower outside" {
			# Interleaved Base, Near, Far per round: Base 10/20/30, Near 21/22/23, Far 50/60/70.
			foreach ($total in 10, 21, 50, 20, 22, 60, 30, 23, 70) { $script:ScriptedRows.Enqueue(@{ Total = $total }) }

			$summary = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 3 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Base' }, @{ Name = 'Near' }, @{ Name = 'Far' } -Configuration $script:Configuration -ResultPath $script:ResultFile)

			@($summary | Where-Object Variant -eq 'Base')[0].Verdict | Should -Be 'Reference'
			@($summary | Where-Object Variant -eq 'Near')[0].Effect | Should -Be 2
			@($summary | Where-Object Variant -eq 'Near')[0].Verdict | Should -Be 'Noise'
			@($summary | Where-Object Variant -eq 'Far')[0].Effect | Should -Be 40
			@($summary | Where-Object Variant -eq 'Far')[0].Verdict | Should -Be 'Slower'
		}

		It "uses the given teardown instead of Kill-All" {
			$script:TeardownCalls = 0

			Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'Only' } -Teardown { $script:TeardownCalls++ } -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			$script:TeardownCalls | Should -Be 1
			Should -Invoke Kill-All -Times 0 -Exactly
		}

		It "summarizes with medians, clean medians and retry counts" {
			foreach ($scripted in @(@{ Total = 10; Attempts = 1 }, @{ Total = 30; Attempts = 1 }, @{ Total = 20; Attempts = 2 }, @{ Total = 100; Attempts = 1 })) { $script:ScriptedRows.Enqueue($scripted) }

			$summary = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 4 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'A' } -Configuration $script:Configuration -ResultPath $script:ResultFile)

			$summary.Count | Should -Be 1
			$summary[0].Variant | Should -Be 'A'
			$summary[0].Runs | Should -Be 4
			$summary[0].Clean | Should -Be 3
			$summary[0].Retries | Should -Be 1
			$summary[0].NotApplied | Should -Be 0
			$summary[0].MedianTotal | Should -Be 25
			$summary[0].CleanMedianTotal | Should -Be 30
			$summary[0].MinTotal | Should -Be 10
			$summary[0].MaxTotal | Should -Be 100
			$summary[0].MedianFancyZones | Should -Be 1
			$summary[0].MedianPositionSnap | Should -Be 2
		}

		It "attributes interleaved rows to the right variant" {
			# Baseline rows 10 and 20, Hotkeys rows 40 and 60, interleaved: B, H, B, H.
			foreach ($scripted in @(@{ Total = 10 }, @{ Total = 40 }, @{ Total = 20 }, @{ Total = 60 })) { $script:ScriptedRows.Enqueue($scripted) }

			$summary = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 2 -WarmUp 0 -SettleSeconds 0 -Setting FancyZonesApplyMethod -Configuration $script:Configuration -ResultPath $script:ResultFile)

			@($summary | Where-Object Variant -eq 'Baseline')[0].MedianTotal | Should -Be 15
			@($summary | Where-Object Variant -eq 'ApplyMethod=Hotkeys')[0].MedianTotal | Should -Be 50
		}

		It "records an open that produced no benchmark row as NoRow and carries on" {
			$script:ScriptedRows.Enqueue(@{ Skip = $true })
			$script:ScriptedRows.Enqueue(@{ Total = 12 })

			$result = Measure-WorkspaceOpen -Workspace WinuX -Runs 2 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'A' } -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			$result.Runs.Count | Should -Be 2
			$result.Runs[0].Outcome | Should -Be 'NoRow'
			$result.Runs[0].Attempts | Should -Be 0
			$result.Runs[1].Outcome | Should -Be 'Applied'
			$result.Summary[0].NotApplied | Should -Be 1
			$result.Summary[0].Clean | Should -Be 1
			$result.Summary[0].CleanMedianTotal | Should -Be 12
		}

		It "records a throwing open as Error and still restores the configuration" {
			$script:ScriptedRows.Enqueue(@{ Throw = $true })

			$result = Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Setting WorkspaceLayoutPrepareEarly -Configuration $script:Configuration -ResultPath $script:ResultFile -PassThru

			$result.Runs[0].Outcome | Should -Be 'Error'
			$result.Runs[0].Actions | Should -Match 'open exploded'
			$script:Configuration.ContainsKey('WorkspaceLayoutPrepareEarly') | Should -BeFalse
			$script:Configuration.ContainsKey('WorkspaceBenchmark') | Should -BeFalse
		}

		It "writes every open, warm-ups included, to the result file with the flags in effect" {
			Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 1 -SettleSeconds 0 -Setting WorkspaceLayoutPipelining -Configuration $script:Configuration -ResultPath $script:ResultFile | Out-Null

			$rows = @(Import-Csv -LiteralPath $script:ResultFile)
			$rows.Count | Should -Be 3
			$rows[0].Measured | Should -Be 'False'
			$rows[0].Round | Should -Be '0'
			$rows[1].Variant | Should -Be 'Baseline'
			$rows[1].WorkspaceLayoutPipelining | Should -Be 'On'
			$rows[2].Variant | Should -Be 'Pipelining=Off'
			$rows[2].WorkspaceLayoutPipelining | Should -Be 'Off'
			$rows[2].FancyZonesApplyMethod | Should -Be 'File'
			$rows[2].Settings | Should -Be 'Pipelining=Off'
			$rows[2].TotalSeconds | Should -Be '10'
			($rows | Select-Object -ExpandProperty Session -Unique).Count | Should -Be 1
		}

		It "reads back only the rows the open appended, ignoring older rows of the same workspace" {
			Write-WorkspaceBenchmark -Workspace WinuX -TotalSeconds 999 -BenchmarkPath $script:BenchmarkFile -Quiet
			$script:ScriptedRows.Enqueue(@{ Total = 7 })

			$summary = @(Measure-WorkspaceOpen -Workspace WinuX -Runs 1 -WarmUp 0 -SettleSeconds 0 -Variant @{ Name = 'A' } -Configuration $script:Configuration -ResultPath $script:ResultFile)

			$summary[0].MedianTotal | Should -Be 7
		}
	}
}

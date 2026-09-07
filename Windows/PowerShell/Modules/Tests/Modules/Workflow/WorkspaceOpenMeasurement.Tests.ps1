#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Get-WorkspaceBenchmarkPath.ps1"
	. "$FunctionsPath\Get-WorkspaceOpenMeasurementPath.ps1"
	. "$FunctionsPath\Read-WorkspaceOpenMeasurement.ps1"
	. "$FunctionsPath\ConvertTo-WorkspaceOpenSummary.ps1"
	. "$FunctionsPath\Get-WorkspaceOpenMeasurement.ps1"

	foreach ($name in @('Write-LogTitle', 'Write-LogStep', 'Write-LogWarning')) {
		if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
			Set-Item -Path "function:script:$name" -Value { param([string]$Message, [switch]$NoLeadingNewline, $Style) }
		}
	}
	if (-not (Get-Command Get-LogPath -ErrorAction SilentlyContinue)) {
		function Get-LogPath { param([switch]$ErrorLog, [switch]$Directory) }
	}
	if (-not (Get-Command Get-WorkspaceStatePath -ErrorAction SilentlyContinue)) {
		function Get-WorkspaceStatePath { }
	}

	# One per-run row as Measure-WorkspaceOpen writes it, with only the columns the summary reads.
	function New-RunRow {
		param(
			[string]$Session = 'S1', [string]$Variant = 'Baseline', [int]$Round = 1, [bool]$Measured = $true, [int]$Position = 1,
			[double]$Total = 10, [int]$Attempts = 1, [string]$Outcome = 'Applied', [hashtable]$Phases = @{},
			[string]$Workspace = 'WinuX', [string]$Project = '', [string]$Timestamp = '2026-09-07 13:58:04'
		)
		$invariant = [System.Globalization.CultureInfo]::InvariantCulture
		[PSCustomObject]@{
			Session = $Session; Workspace = $Workspace; Project = $Project; Variant = $Variant; Round = $Round; Measured = $Measured; Position = $Position
			Settings = $(if ($Variant -eq 'Baseline') { '' } else { $Variant })
			FancyZonesApplyMethod = 'File'; WorkspaceLayoutPipelining = 'On'; WorkspaceLayoutPrepareEarly = 'On'
			Timestamp = $Timestamp; Mode = 'Plain'; Outcome = $Outcome; Attempts = $Attempts
			TotalSeconds = $Total; ActionsSeconds = 1; LayoutSeconds = ($Total - 1)
			PreambleSeconds = 0; DesktopsSeconds = 0
			FancyZonesSeconds = [double]$(if ($null -ne $Phases.FancyZones) { $Phases.FancyZones } else { 1 })
			WaitSeconds = [double]$(if ($null -ne $Phases.Wait) { $Phases.Wait } else { 2 })
			NormalizeSeconds = 0
			PositionSeconds = [double]$(if ($null -ne $Phases.Position) { $Phases.Position } else { 1 })
			SnapSeconds = [double]$(if ($null -ne $Phases.Snap) { $Phases.Snap } else { 1 })
			VerifySeconds = [double]$(if ($null -ne $Phases.Verify) { $Phases.Verify } else { 0.5 })
			RetrySeconds = 0; SaveSeconds = 0; OtherSeconds = 0; Actions = ''
		} | ForEach-Object {
			# Written culture-invariant, like the real file.
			$csv = [ordered]@{}
			foreach ($property in $_.PSObject.Properties) {
				$value = $property.Value
				$csv[$property.Name] = if ($value -is [double]) { $value.ToString('0.##', $invariant) } elseif ($value -is [int]) { $value.ToString($invariant) } elseif ($value -is [bool]) { $value.ToString() } else { [string]$value }
			}
			[PSCustomObject]$csv
		}
	}

	function Write-RunRows {
		param([object[]]$Rows, [string]$Path)
		$Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
	}
}

Describe "ConvertTo-WorkspaceOpenSummary" {
	It "returns nothing for no rows or for warm-ups only" {
		@(ConvertTo-WorkspaceOpenSummary -Row @()).Count | Should -Be 0
		@(ConvertTo-WorkspaceOpenSummary -Row @((New-RunRow -Measured $false -Round 0))).Count | Should -Be 0
	}

	It "summarizes per variant in the order the variants first ran, with medians and clean medians" {
		$rows = @(
			(New-RunRow -Variant 'B' -Position 1 -Total 50)
			(New-RunRow -Variant 'A' -Position 2 -Total 10)
			(New-RunRow -Variant 'B' -Position 3 -Total 60 -Attempts 2)
			(New-RunRow -Variant 'A' -Position 4 -Total 30)
			(New-RunRow -Variant 'A' -Position 5 -Total 20 -Outcome 'Escalated')
		)

		$summary = @(ConvertTo-WorkspaceOpenSummary -Row $rows)

		$summary.Variant | Should -Be @('B', 'A')
		$a = $summary[1]
		$a.Runs | Should -Be 3
		$a.Clean | Should -Be 2
		$a.NotApplied | Should -Be 1
		$a.MedianTotal | Should -Be 20
		$a.CleanMedianTotal | Should -Be 20
		$a.MinTotal | Should -Be 10
		$a.MaxTotal | Should -Be 30
		$summary[0].Retries | Should -Be 1
		$summary[0].CleanMedianTotal | Should -Be 50
	}

	It "compares every variant with the first one: Noise inside the spread, Faster or Slower outside" {
		$rows = @(
			(New-RunRow -Variant 'Baseline' -Position 1 -Total 10)
			(New-RunRow -Variant 'Near' -Position 2 -Total 21)
			(New-RunRow -Variant 'Far' -Position 3 -Total 50)
			(New-RunRow -Variant 'Quick' -Position 4 -Total 2)
			(New-RunRow -Variant 'Baseline' -Position 5 -Total 20)
			(New-RunRow -Variant 'Near' -Position 6 -Total 22)
			(New-RunRow -Variant 'Far' -Position 7 -Total 60)
			(New-RunRow -Variant 'Quick' -Position 8 -Total 3)
			(New-RunRow -Variant 'Baseline' -Position 9 -Total 30)
			(New-RunRow -Variant 'Near' -Position 10 -Total 23)
			(New-RunRow -Variant 'Far' -Position 11 -Total 70)
			(New-RunRow -Variant 'Quick' -Position 12 -Total 4)
		)

		$summary = @(ConvertTo-WorkspaceOpenSummary -Row $rows)
		$byName = @{}
		foreach ($entry in $summary) { $byName[$entry.Variant] = $entry }

		$byName['Baseline'].Verdict | Should -Be 'Reference'
		$byName['Baseline'].Spread | Should -Be 20
		# +2 s against a 20 s baseline spread is inside the noise.
		$byName['Near'].Effect | Should -Be 2
		$byName['Near'].Verdict | Should -Be 'Noise'
		$byName['Far'].Effect | Should -Be 40
		$byName['Far'].Verdict | Should -Be 'Slower'
		$byName['Quick'].Effect | Should -Be -17
		$byName['Quick'].Verdict | Should -Be 'Faster'
	}

	It "takes the reference by name and falls back to the plain median for a variant without a clean run" {
		$rows = @(
			(New-RunRow -Variant 'A' -Position 1 -Total 10)
			(New-RunRow -Variant 'B' -Position 2 -Total 40 -Attempts 2)
			(New-RunRow -Variant 'A' -Position 3 -Total 12)
			(New-RunRow -Variant 'B' -Position 4 -Total 44 -Attempts 3)
		)

		$summary = @(ConvertTo-WorkspaceOpenSummary -Row $rows -Reference 'B')

		@($summary | Where-Object Variant -eq 'B')[0].Verdict | Should -Be 'Reference'
		@($summary | Where-Object Variant -eq 'B')[0].Clean | Should -Be 0
		# A's clean median 11 against B's plain median 42.
		@($summary | Where-Object Variant -eq 'A')[0].Effect | Should -Be -31
		@($summary | Where-Object Variant -eq 'A')[0].Verdict | Should -Be 'Faster'
	}

	It "accepts the rows from the pipeline" {
		$summary = @((New-RunRow -Variant 'Only' -Total 5), (New-RunRow -Variant 'Only' -Position 2 -Total 7) | ConvertTo-WorkspaceOpenSummary)

		$summary.Count | Should -Be 1
		$summary[0].MedianTotal | Should -Be 6
	}
}

Describe "Read-WorkspaceOpenMeasurement" {
	BeforeEach {
		$script:ResultFile = Join-Path $TestDrive ("Measurements_" + [guid]::NewGuid().ToString('N') + ".csv")
	}

	It "reads a missing file as an empty result" {
		@(Read-WorkspaceOpenMeasurement -ResultPath $script:ResultFile).Count | Should -Be 0
	}

	It "types the columns and orders by session then position" {
		Write-RunRows -Path $script:ResultFile -Rows @(
			(New-RunRow -Session 'S2' -Position 2 -Total 20.5 -Attempts 2)
			(New-RunRow -Session 'S1' -Position 1 -Measured $false -Round 0)
			(New-RunRow -Session 'S2' -Position 1 -Total 7)
		)

		$rows = @(Read-WorkspaceOpenMeasurement -ResultPath $script:ResultFile)

		$rows.Count | Should -Be 3
		@($rows | ForEach-Object { "$($_.Session)/$($_.Position)" }) | Should -Be @('S1/1', 'S2/1', 'S2/2')
		$rows[0].Measured | Should -BeOfType [bool]
		$rows[0].Measured | Should -BeFalse
		$rows[2].TotalSeconds | Should -BeOfType [double]
		$rows[2].TotalSeconds | Should -Be 20.5
		$rows[2].Attempts | Should -BeOfType [int]
		$rows[2].Attempts | Should -Be 2
		$rows[2].Position | Should -BeOfType [int]
	}

	It "keeps only the requested sessions" {
		Write-RunRows -Path $script:ResultFile -Rows @((New-RunRow -Session 'S1'), (New-RunRow -Session 'S2'), (New-RunRow -Session 'S3'))

		@(Read-WorkspaceOpenMeasurement -Session 'S1', 'S3' -ResultPath $script:ResultFile).Session | Should -Be @('S1', 'S3')
	}

	It "throws on a file it cannot read" {
		Mock Import-Csv { throw "locked" }
		Set-Content -LiteralPath $script:ResultFile -Value 'x'

		{ Read-WorkspaceOpenMeasurement -ResultPath $script:ResultFile } | Should -Throw
	}
}

Describe "Get-WorkspaceOpenMeasurement" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		$script:ResultFile = Join-Path $TestDrive ("Measurements_" + [guid]::NewGuid().ToString('N') + ".csv")
		Write-RunRows -Path $script:ResultFile -Rows @(
			(New-RunRow -Session '20260907-100000' -Position 1 -Total 10 -Timestamp '2026-09-07 10:00:00')
			(New-RunRow -Session '20260907-100000' -Position 2 -Variant 'Flip' -Total 40 -Timestamp '2026-09-07 10:01:00')
			(New-RunRow -Session '20260907-120000' -Position 1 -Measured $false -Round 0 -Total 99 -Project 'Asseto' -Timestamp '2026-09-07 12:00:00')
			(New-RunRow -Session '20260907-120000' -Position 2 -Total 20 -Project 'Asseto' -Timestamp '2026-09-07 12:01:00')
			(New-RunRow -Session '20260907-120000' -Position 3 -Variant 'Flip' -Total 21 -Project 'Asseto' -Timestamp '2026-09-07 12:02:00')
		)
	}

	It "warns and returns nothing when no experiment has been recorded" {
		$result = Get-WorkspaceOpenMeasurement -ResultPath (Join-Path $TestDrive 'nothing-here.csv')

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "summarizes the most recent session by default, warm-ups excluded" {
		$summary = @(Get-WorkspaceOpenMeasurement -ResultPath $script:ResultFile)

		$summary.Count | Should -Be 2
		$summary[0].Variant | Should -Be 'Baseline'
		$summary[0].Runs | Should -Be 1
		$summary[0].MedianTotal | Should -Be 20
		$summary[1].Variant | Should -Be 'Flip'
		$summary[1].Effect | Should -Be 1
	}

	It "summarizes the named session" {
		$summary = @(Get-WorkspaceOpenMeasurement -Session '20260907-100000' -ResultPath $script:ResultFile)

		@($summary | Where-Object Variant -eq 'Flip')[0].MedianTotal | Should -Be 40
	}

	It "warns about an unknown session" {
		$result = Get-WorkspaceOpenMeasurement -Session 'nope' -ResultPath $script:ResultFile

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "lists one row per session with -ListSessions" {
		$sessions = @(Get-WorkspaceOpenMeasurement -ListSessions -ResultPath $script:ResultFile)

		$sessions.Count | Should -Be 2
		$sessions[0].Session | Should -Be '20260907-100000'
		$sessions[0].Opens | Should -Be 2
		$sessions[0].Variants | Should -Be 2
		$sessions[1].Project | Should -Be 'Asseto'
		$sessions[1].Opens | Should -Be 3
		$sessions[1].Measured | Should -Be 2
		$sessions[1].Started | Should -Be '2026-09-07 12:00:00'
	}

	It "renders a table with -Formatted and hands the rows back with -PassThru" {
		$output = @(Get-WorkspaceOpenMeasurement -Formatted -ResultPath $script:ResultFile)
		$output[0].GetType().FullName | Should -BeLike 'Microsoft.PowerShell.Commands.Internal.Format.*'
		($output | Out-String -Width 500) | Should -Match 'Verdict'

		$result = Get-WorkspaceOpenMeasurement -PassThru -ResultPath $script:ResultFile
		$result.Session | Should -Be '20260907-120000'
		@($result.Runs).Count | Should -Be 3
		@($result.Summary).Count | Should -Be 2
	}
}

Describe "Get-WorkspaceOpenMeasurementPath" {
	It "puts the result file beside the benchmark file" {
		Mock Get-WorkspaceBenchmarkPath { 'C:\Users\You\Logs\WorkspaceBenchmark.csv' }

		Get-WorkspaceOpenMeasurementPath | Should -Be 'C:\Users\You\Logs\WorkspaceOpenMeasurements.csv'
	}
}

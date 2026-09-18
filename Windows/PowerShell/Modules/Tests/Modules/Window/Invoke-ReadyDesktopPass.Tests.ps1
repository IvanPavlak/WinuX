#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\New-WindowClaimSet.ps1"
	. "$FunctionsPath\New-WorkspaceLayoutPipelineState.ps1"
	. "$FunctionsPath\Invoke-ReadyDesktopPass.ps1"

	# Everything the pass reaches, stubbed so Mock attaches in this scope instead of the Window,
	# Helper and Logging modules.
	function Set-WindowLayouts { param($LayoutConfig, $DesktopNumbers, $MonitorInfo, $MonitorConfig, $Claims, $ExpectedWindowState, $DesktopOffset, [switch]$KeepPositionedWindows, $AbandonedEntries) @() }
	function Resize-PositionedWindows { param($DesktopNumbers) @{ FailedWindows = @() } }
	function Snap-AllWindows { param($DesktopOffset, $DesktopCount, $DesktopNumbers, $ZoneReset) $true }
	function Loading-Spinner { param([switch]$Start, [switch]$Stop, [switch]$Pause, [switch]$Resume, $Spinner, $Label, [switch]$Completed, [switch]$Discard) }
	function Test-LogVerbose { $false }
	function Write-LogDebug { param([string]$Message, [string]$Style) }
	function Write-LogWarning { param([string]$Message) }

	function New-TestWindow {
		param([int]$Handle, [string]$Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title; Left = 0; Top = 0; Width = 800; Height = 600 }
	}
}

Describe "Invoke-ReadyDesktopPass" {
	BeforeEach {
		Mock Test-LogVerbose { $false }
		Mock Write-LogDebug { }
		Mock Loading-Spinner { }
		Mock Resize-PositionedWindows { @{ FailedWindows = @() } }
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 1; FailedWindows = @() } }
		$script:LastSnapAllWindowsResult = $null

		# Two desktops; desktop 2 is the one reported ready.
		$script:layout = @(
			@{ ProcessName = 'Code'; WindowTitle = '*Code*'; DesktopNumber = 1 }
			@{ ProcessName = 'WindowsTerminal'; DesktopNumber = 2 }
		)
		$script:phases = @()
		$script:recordPhase = { param([string]$Phase) $script:phases += $Phase }
		$script:zoneReset = { param([string]$Reason) }
		$script:claims = New-WindowClaimSet -Existing @([IntPtr]5)
		$script:pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims -MonitorInfo @() -MonitorConfig @{ MonitorA = @{} } `
			-DesktopOffset 0 -DesktopCount 2 -ZoneReset $script:zoneReset -RecordPhase $script:recordPhase -SpinnerActive

		$script:readyEntries = @(@{ LayoutEntry = $script:layout[1]; Window = (New-TestWindow -Handle 102 -Title 'Terminal') })
		$script:placedRow = [PSCustomObject]@{ Status = 'Configured'; Handle = [IntPtr]102; ProcessName = 'WindowsTerminal'; DesktopNumber = 2; EntryKey = '2|||WindowsTerminal|' }

		$script:layoutCalls = @()
		Mock Set-WindowLayouts {
			$script:layoutCalls += [PSCustomObject]@{
				Entries    = @($LayoutConfig)
				Desktops   = $DesktopNumbers
				Keep       = [bool]$KeepPositionedWindows
				Claims     = $Claims
				Expected   = $ExpectedWindowState
				Abandoned  = $AbandonedEntries
				# $PSBoundParameters is not populated inside a Pester mock body; the stub's untyped
				# parameter is $null when the pass did not forward the entries.
				HasAbandon = ($null -ne $AbandonedEntries)
			}
			@($script:placedRow)
		}
	}

	It "does not run a layout pass when no ready entry carries a window" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries @() -StableWindowHandles @([IntPtr]102)

		Should -Invoke Set-WindowLayouts -Times 0 -Exactly
		Should -Invoke Snap-AllWindows -Times 0 -Exactly
		$script:pipeline.PipelinedDesktops.Count | Should -Be 0
		# The spinner is still paused and resumed around the attempt.
		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Pause }
		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Resume }
	}

	It "hands the whole layout to Set-WindowLayouts restricted to the ready desktop, appending to the shared tracking" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102, [IntPtr]777)

		$script:layoutCalls.Count | Should -Be 1
		$script:layoutCalls[0].Entries.Count | Should -Be 2
		@($script:layoutCalls[0].Desktops) | Should -Be @(2)
		$script:layoutCalls[0].Keep | Should -BeTrue
		$script:layoutCalls[0].Expected.ContainsKey([IntPtr]102) | Should -BeTrue
		$script:layoutCalls[0].Expected[[IntPtr]102].Title | Should -Be 'Terminal'
	}

	It "restricts the claims to the stable handles plus the ready windows, keeping the open's other rules" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]777, [IntPtr]::Zero, $null)

		$passClaims = $script:layoutCalls[0].Claims
		$passClaims.HasCandidates | Should -BeTrue
		$passClaims.Candidates.Contains([IntPtr]102) | Should -BeTrue
		$passClaims.Candidates.Contains([IntPtr]777) | Should -BeTrue
		$passClaims.Candidates.Count | Should -Be 2
		$passClaims.Existing.Contains([IntPtr]5) | Should -BeTrue
		# The shared claim set itself is never narrowed.
		$script:claims.HasCandidates | Should -BeFalse
	}

	It "records a placed result into the tallies and marks its window excluded for every later pass" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		$script:pipeline.PipelinedResults.Count | Should -Be 1
		$script:pipeline.PipelinedResults[0].Handle | Should -Be ([IntPtr]102)
		$script:pipeline.PipelinedEntryKeys.Contains('2|||WindowsTerminal|') | Should -BeTrue
		$script:claims.Excluded.Contains([IntPtr]102) | Should -BeTrue
		$script:claims.TestClaimable([IntPtr]102) | Should -BeFalse
		$script:pipeline.PipelinedDesktops[2] | Should -BeTrue
	}

	It "resizes and snaps the ready desktop alone with the pipeline's zone reset and desktop count" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		Should -Invoke Resize-PositionedWindows -Times 1 -Exactly -ParameterFilter { @($DesktopNumbers) -contains 2 }
		Should -Invoke Snap-AllWindows -Times 1 -Exactly -ParameterFilter {
			$DesktopOffset -eq 0 -and $DesktopCount -eq 2 -and @($DesktopNumbers) -contains 2 -and $ZoneReset -eq $script:zoneReset
		}
	}

	It "drops a Not Found row so the pass after the wait places that entry" {
		Mock Set-WindowLayouts {
			@(
				$script:placedRow
				[PSCustomObject]@{ Status = 'Not Found'; ProcessName = 'Code'; DesktopNumber = 2; EntryKey = '2|||Code|*Code*' }
			)
		}

		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		$script:pipeline.PipelinedResults.Count | Should -Be 1
		$script:pipeline.PipelinedEntryKeys.Count | Should -Be 1
		$script:pipeline.PipelinedEntryKeys.Contains('2|||Code|*Code*') | Should -BeFalse
		$script:pipeline.PipelinedDesktops[2] | Should -BeTrue
	}

	It "leaves the desktop to the pass after the wait when nothing could be placed" {
		Mock Set-WindowLayouts { @([PSCustomObject]@{ Status = 'Not Found'; ProcessName = 'WindowsTerminal'; DesktopNumber = 2; EntryKey = '2|||WindowsTerminal|' }) }

		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		$script:pipeline.PipelinedResults.Count | Should -Be 0
		$script:pipeline.PipelinedDesktops.Count | Should -Be 0
		$script:claims.Excluded.Count | Should -Be 0
		Should -Invoke Resize-PositionedWindows -Times 0 -Exactly
		Should -Invoke Snap-AllWindows -Times 0 -Exactly
		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Resume }
	}

	It "collects the desktop's snap failures for the first attempt's tally" {
		$failure = [PSCustomObject]@{ Handle = [IntPtr]102; WindowTitle = 'Terminal'; Error = 'Snap FAILED' }
		Mock Snap-AllWindows { $script:LastSnapAllWindowsResult = [PSCustomObject]@{ SnappedCount = 0; FailedWindows = @($failure) } }

		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		$script:pipeline.PipelinedSnapFailures.Count | Should -Be 1
		$script:pipeline.PipelinedSnapFailures[0].Handle | Should -Be ([IntPtr]102)
		# A failed snap still counts the desktop as handled here; the retry ladder deals with it.
		$script:pipeline.PipelinedDesktops[2] | Should -BeTrue
	}

	It "books its time to Wait, then Position, then Snap" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		$script:phases | Should -Be @('Wait', 'Position', 'Snap')
	}

	It "pauses the spinner before the pass and resumes it after" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Pause }
		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Resume }
	}

	It "never touches the spinner when none is running" {
		$quiet = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims -DesktopCount 2 -RecordPhase $script:recordPhase

		Invoke-ReadyDesktopPass -Pipeline $quiet -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		Should -Invoke Loading-Spinner -Times 0 -Exactly
	}

	It "leaves every tally empty and resumes the spinner when the layout pass throws" {
		Mock Set-WindowLayouts { throw 'FancyZones is gone' }

		{ Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102) } | Should -Not -Throw

		$script:pipeline.PipelinedResults.Count | Should -Be 0
		$script:pipeline.PipelinedEntryKeys.Count | Should -Be 0
		$script:pipeline.PipelinedDesktops.Count | Should -Be 0
		$script:claims.Excluded.Count | Should -Be 0
		Should -Invoke Snap-AllWindows -Times 0 -Exactly
		Should -Invoke Loading-Spinner -Times 1 -Exactly -ParameterFilter { $Resume }
		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -match 'failed - leaving it to the main pass' }
	}

	It "forwards the abandoned entries only when there are any" {
		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102) -AbandonedEntries @()
		$script:layoutCalls[0].HasAbandon | Should -BeFalse

		Invoke-ReadyDesktopPass -Pipeline $script:pipeline -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102) -AbandonedEntries @($script:layout[0])
		$script:layoutCalls[1].HasAbandon | Should -BeTrue
		@($script:layoutCalls[1].Abandoned).Count | Should -Be 1
		@($script:layoutCalls[1].Abandoned)[0].ProcessName | Should -Be 'Code'
	}

	It "applies the pipeline's desktop offset to the display desktop it resizes and snaps" {
		$offset = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims -DesktopOffset 3 -DesktopCount 2 -RecordPhase $script:recordPhase

		Invoke-ReadyDesktopPass -Pipeline $offset -ReadyDesktopNumber 2 -ReadyEntries $script:readyEntries -StableWindowHandles @([IntPtr]102)

		# The layout pass still gets the layout's own desktop number; the tracking carries the offset.
		@($script:layoutCalls[0].Desktops) | Should -Be @(2)
		Should -Invoke Resize-PositionedWindows -Times 1 -Exactly -ParameterFilter { @($DesktopNumbers) -contains 5 }
		Should -Invoke Snap-AllWindows -Times 1 -Exactly -ParameterFilter { @($DesktopNumbers) -contains 5 }
		$offset.PipelinedDesktops[2] | Should -BeTrue
	}
}
